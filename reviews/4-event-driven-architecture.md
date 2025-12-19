# Event-Driven Architecture Review

## Summary
The codebase implements event sourcing patterns with events stored in an append-only event store. However, the event-driven architecture is incomplete: events are stored but not published, there's no event-driven communication between components, and the projection is updated synchronously rather than reacting to events. The architecture is more "event-stored" than "event-driven."

---

## 🟢 Strengths

### 1. Event Sourcing Foundation
**Location:** `lib/adapters/event_store.ex`

Events are persisted in an append-only manner with:
- Immutable event storage (DynamoDB with version-based optimistic locking)
- Stream-based organization (events grouped by aggregate)
- Version sequencing for ordering guarantees

```elixir
opts = [condition_expression: "attribute_not_exists(version)"]
case client.put_item(@events_table, item, opts) |> ExAws.request() do
  {:ok, _} -> {:ok, event.id}
  {:error, reason} -> {:error, {:write_error, reason}}
end
```

### 2. CloudEvents Specification
**Location:** `lib/event/event.ex`

Events follow the CloudEvents standard, providing:
- Structured metadata (id, source, type, time)
- Versioning (specversion "1.0")
- Extensibility for future needs

This is good for interoperability and future integration with event brokers.

### 3. Stream-Based Identity
**Location:** `lib/event/event.ex:52-60`

Events are organized into streams by aggregate:
```elixir
def stream_id_for(%{id: id} = data) do
  aggregate_prefix = data.__struct__ |> Module.split() |> List.last() |> Macro.underscore()
  "#{aggregate_prefix}-#{id}"
end
```

This enables event replay, aggregate reconstruction, and audit trails.

### 4. Optimistic Concurrency Control
Both event store and projection use version-based concurrency:
```elixir
# EventStore
condition_expression: "attribute_not_exists(version)"

# PizzaProjection  
condition_expression: "attribute_not_exists(version) OR :incoming_version > version"
```

Prevents lost updates and ensures consistency.

---

## 🟡 Areas for Improvement

### 1. **Synchronous Projection Updates**
**Location:** `lib/application/dispatcher.ex:43-53`

```elixir
def handle_call({:save_pizza, attrs}, _from, state) do
  with {:ok, pizza} <- build_pizza(attrs),
       {:ok, version} <- EventStoreProcess.next_version(state.event_store, pizza),
       {:ok, event} <- build_event(pizza, state.clock, version),
       {:ok, _} <- EventStoreProcess.store(state.event_store, event),
       {:ok, _} <- PizzaProjectionProcess.save(state.pizza_projection, event) do
    {:reply, {:ok, pizza}, state}
  end
end
```

**Issue:** The projection update happens **synchronously** in the same transaction chain. This is NOT event-driven architecture - it's event sourcing with synchronous read models.

**Problems:**
- Tight coupling between write and read sides
- Projection failure prevents command completion
- Cannot scale projections independently
- No eventual consistency model
- Additional projections require dispatcher changes

**True Event-Driven Approach:**
```elixir
def handle_call({:save_pizza, attrs}, _from, state) do
  with {:ok, pizza} <- build_pizza(attrs),
       {:ok, version} <- EventStoreProcess.next_version(state.event_store, pizza),
       {:ok, event} <- build_event(pizza, state.clock, version),
       {:ok, _} <- EventStoreProcess.store(state.event_store, event),
       :ok <- publish_event(event) do  # Publish, don't call projection
    {:reply, {:ok, pizza}, state}
  end
end

# Projection subscribes to events
defmodule Pizza.Projections.PizzaMenuProjection do
  use GenServer
  
  def init(_) do
    :ok = EventBus.subscribe([:pizza_saved])
    {:ok, %{}}
  end
  
  def handle_info({:event, event}, state) do
    handle_event(event)
    {:noreply, state}
  end
end
```

### 2. **No Event Publishing Mechanism**
**Issue:** Events are stored but never published. There's no:
- Event bus or broker
- Pub/sub mechanism
- Event notification system
- Subscription management

**Current flow:**
```
Command → Store Event → Update Projection
                ↓
           (stored, never published)
```

**Event-driven flow:**
```
Command → Store Event → Publish Event
                           ↓
                    ┌──────┴──────┐
                    ↓             ↓
              Projection    Other Handlers
```

**Recommendation:** Add event publishing infrastructure:

```elixir
defmodule Pizza.Infrastructure.EventBus do
  @moduledoc """
  In-process event bus for event-driven communication.
  For production, consider: EventStore, Commanded, or external broker.
  """
  
  def start_link(_opts) do
    Registry.start_link(keys: :duplicate, name: __MODULE__)
  end
  
  def subscribe(event_types) when is_list(event_types) do
    Enum.each(event_types, fn type ->
      Registry.register(__MODULE__, type, [])
    end)
  end
  
  def publish(event) do
    Registry.dispatch(__MODULE__, event.type, fn entries ->
      for {pid, _} <- entries, do: send(pid, {:event, event})
    end)
  end
end
```

### 3. **Single Event Type**
**Location:** `lib/application/dispatcher.ex:67`

```elixir
event = CloudEvent.new_v1(:pizza_app, :pizza_saved, clock.(), pizza, version)
```

**Issue:** Only one event type (`:pizza_saved`) for all pizza operations. This loses semantic meaning.

**Missing event types:**
- `:pizza_created` - New pizza added to menu
- `:pizza_price_changed` - Price updated
- `:pizza_renamed` - Name changed
- `:pizza_discontinued` - Removed from menu

**Why this matters:**
- Different projections care about different events
- Event handlers can subscribe to specific event types
- Business processes can react to specific changes
- Audit logs are more meaningful

**Recommendation:**
```elixir
# Domain produces specific events
defmodule Pizza.Core.Events do
  defmodule PizzaCreated do
    @enforce_keys [:pizza_id, :name, :price, :occurred_at]
    defstruct [:pizza_id, :name, :price, :occurred_at]
  end
  
  defmodule PriceChanged do
    @enforce_keys [:pizza_id, :old_price, :new_price, :reason, :occurred_at]
    defstruct [:pizza_id, :old_price, :new_price, :reason, :occurred_at]
  end
end

# Dispatcher maps to CloudEvents
def handle_call({:create_pizza, attrs}, _from, state) do
  with {:ok, pizza, events} <- Pizza.create(attrs.name, attrs.price),
       :ok <- persist_and_publish(events, pizza, state) do
    {:reply, {:ok, pizza}, state}
  end
end

defp persist_and_publish(domain_events, aggregate, state) do
  domain_events
  |> Enum.reduce_while(:ok, fn event, _acc ->
    cloud_event = to_cloud_event(event, aggregate)
    
    with {:ok, _} <- EventStore.store(cloud_event),
         :ok <- EventBus.publish(cloud_event) do
      {:cont, :ok}
    else
      error -> {:halt, error}
    end
  end)
end
```

### 4. **No Event Versioning Strategy**
**Issue:** The `CloudEvent` has a `version` field (event sequence in stream) but no event schema versioning.

**What happens when:**
- Event structure changes (add/remove fields)?
- Business rules evolve?
- New event types are introduced?

**Recommendation:** Implement event versioning:

```elixir
defmodule Pizza.Core.Events.PizzaCreated do
  @version 2  # Schema version
  
  defstruct [
    :pizza_id,
    :name,
    :price,
    :occurred_at,
    :category  # Added in v2
  ]
  
  def from_map(%{"_version" => 1} = data) do
    # Upcaster: v1 → v2
    %__MODULE__{
      pizza_id: data["pizza_id"],
      name: data["name"],
      price: data["price"],
      occurred_at: data["occurred_at"],
      category: "standard"  # Default for old events
    }
  end
  
  def from_map(%{"_version" => 2} = data) do
    # Current version
    struct(__MODULE__, atomize_keys(data))
  end
end
```

### 5. **No Event Replay or Reconstitution**
**Issue:** The event store stores events but provides no way to:
- Replay events for a stream
- Reconstruct aggregate state from events
- Build new projections from historical events

**Missing functionality:**
```elixir
# Should exist but doesn't
EventStore.get_stream(stream_id, from_version \\ 0)
EventStore.replay_stream(stream_id, handler)
```

**Recommendation:** Add stream replay:

```elixir
defmodule Pizza.Adapters.EventStore do
  @impl true
  def get_stream(stream_id, opts \\ []) do
    from_version = Keyword.get(opts, :from_version, 0)
    
    query_opts = [
      key_condition_expression: "#stream_id = :stream_id AND version >= :from_version",
      expression_attribute_names: %{"#stream_id" => "stream_id"},
      expression_attribute_values: %{
        stream_id: stream_id,
        from_version: from_version
      },
      scan_index_forward: true
    ]
    
    case client.query(@events_table, query_opts) |> ExAws.request() do
      {:ok, %{"Items" => items}} ->
        events = Enum.map(items, &decode_event/1)
        {:ok, events}
      
      error -> error
    end
  end
  
  @impl true
  def replay_stream(stream_id, handler) when is_function(handler, 1) do
    {:ok, events} = get_stream(stream_id)
    Enum.each(events, handler)
    :ok
  end
end
```

### 6. **Projection as Special Case, Not Generic Pattern**
**Location:** `lib/adapters/pizza_projection.ex`

**Issue:** The projection is hardcoded specifically for pizzas. There's no generic projection infrastructure.

**Problems:**
- Can't easily add new projections (e.g., price history, audit log)
- Each projection needs custom process, adapter, port
- No shared projection patterns (idempotency, checkpointing)

**Recommendation:** Extract generic projection infrastructure:

```elixir
defmodule Pizza.Infrastructure.Projection do
  @callback handle_event(CloudEvent.t(), state :: term()) :: 
    {:ok, new_state :: term()} | {:error, term()}
  
  @callback initial_state() :: term()
  
  defmacro __using__(_opts) do
    quote do
      use GenServer
      @behaviour Pizza.Infrastructure.Projection
      
      def start_link(opts) do
        GenServer.start_link(__MODULE__, opts, name: __MODULE__)
      end
      
      def init(opts) do
        event_types = Keyword.fetch!(opts, :subscribe_to)
        EventBus.subscribe(event_types)
        
        {:ok, initial_state()}
      end
      
      def handle_info({:event, event}, state) do
        case handle_event(event, state) do
          {:ok, new_state} -> {:noreply, new_state}
          {:error, reason} -> 
            Logger.error("Projection error: #{inspect(reason)}")
            {:noreply, state}
        end
      end
    end
  end
end

# Usage
defmodule Pizza.Projections.MenuProjection do
  use Pizza.Infrastructure.Projection
  
  @impl true
  def initial_state(), do: %{}
  
  @impl true
  def handle_event(%CloudEvent{type: :pizza_created, data: pizza}, state) do
    # Update read model
    {:ok, Map.put(state, pizza.id, pizza)}
  end
end
```

### 7. **No Dead Letter Queue or Error Handling**
**Issue:** If projection update fails, what happens?
- Current: The whole command fails (synchronous coupling)
- Event-driven: Need retry logic, dead letter queue, monitoring

**Recommendation:**
```elixir
defmodule Pizza.Infrastructure.Projection do
  def handle_info({:event, event}, state) do
    case handle_event(event, state) do
      {:ok, new_state} -> 
        acknowledge_event(event)
        {:noreply, new_state}
      
      {:error, :retriable, reason} ->
        schedule_retry(event, reason)
        {:noreply, state}
      
      {:error, :fatal, reason} ->
        send_to_dead_letter_queue(event, reason)
        {:noreply, state}
    end
  end
  
  defp schedule_retry(event, reason) do
    Process.send_after(self(), {:retry_event, event}, :timer.seconds(5))
  end
end
```

### 8. **Missing Event Metadata**
**Issue:** Events have minimal metadata. Missing:
- Causation ID (what caused this event)
- Correlation ID (trace across services)
- User/actor who triggered the event
- Business context

**Recommendation:**
```elixir
defmodule Pizza.Event.CloudEvent do
  defstruct [
    :id,
    :stream_id,
    :version,
    :source,
    :type,
    :time,
    :data,
    # Add metadata
    :causation_id,    # ID of command/event that caused this
    :correlation_id,  # ID for tracing request flow
    :metadata         # Additional context
  ]
  
  def new_v1(source, type, time, data, version, opts \\ []) do
    %__MODULE__{
      # ... existing fields
      causation_id: Keyword.get(opts, :causation_id),
      correlation_id: Keyword.get(opts, :correlation_id),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end
end
```

### 9. **No Saga or Process Manager Support**
**Issue:** For multi-step business processes (e.g., order fulfillment), there's no coordination mechanism.

**Example scenario:**
```
PizzaCreated → UpdateInventory → NotifyKitchen → UpdateMenu
```

**Missing:** Long-running process coordination, compensating actions, state management

**Recommendation:** (Future consideration)
```elixir
defmodule Pizza.Sagas.MenuPublicationSaga do
  use Pizza.Infrastructure.Saga
  
  def handle_event(%CloudEvent{type: :pizza_created} = event, state) do
    with :ok <- check_inventory(event.data),
         :ok <- notify_kitchen(event.data),
         :ok <- publish_to_menu(event.data) do
      {:completed, state}
    else
      {:error, reason} -> 
        {:compensate, reason, state}
    end
  end
end
```

---

## 🔴 Critical Issues

### 1. **Event Store Used as Database, Not Event Log**
**Severity:** High

**Issue:** The event store is used to determine the next version number:

```elixir
def next_version(%__MODULE__{client: client}, aggregate) do
  query_opts = [
    key_condition_expression: "#stream_id = :stream_id",
    projection_expression: "version",
    scan_index_forward: false,
    limit: 1
  ]
  # Query to find highest version...
end
```

**Problems:**
- Reading from event store on every write (performance bottleneck)
- Event store queried as database, not treated as append-only log
- Tight coupling between command handling and event storage

**In true event sourcing:**
- Aggregate loads its events
- Applies events to rebuild state
- Determines next version from loaded state
- Appends new events with expected version

**Recommendation:** Implement proper aggregate loading:

```elixir
defmodule Pizza.Core.Pizza do
  defstruct [:id, :name, :price, :version]
  
  # Load aggregate from event stream
  def load(stream_id) do
    {:ok, events} = EventStore.get_stream(stream_id)
    
    Enum.reduce(events, %__MODULE__{version: 0}, fn event, pizza ->
      apply_event(pizza, event)
    end)
  end
  
  # Apply event to rebuild state
  defp apply_event(pizza, %CloudEvent{type: :pizza_created, data: data, version: v}) do
    %__MODULE__{
      id: data.id,
      name: data.name,
      price: data.price,
      version: v
    }
  end
  
  defp apply_event(pizza, %CloudEvent{type: :price_changed, data: data, version: v}) do
    %{pizza | price: data.new_price, version: v}
  end
end

# In dispatcher
def handle_call({:change_price, pizza_id, new_price}, _from, state) do
  with {:ok, pizza} <- Pizza.load("pizza-#{pizza_id}"),
       {:ok, updated, events} <- Pizza.change_price(pizza, new_price),
       :ok <- persist_events(events, pizza.version + 1, state) do
    {:reply, {:ok, updated}, state}
  end
end
```

### 2. **Projection is Not Eventually Consistent**
**Severity:** High

**Issue:** The synchronous projection update means:
- Write operations block on projection
- Can't have multiple projections easily
- Can't rebuild projections from events
- Defeats the purpose of CQRS/event sourcing

**Recommendation:** Make projections eventually consistent:

```elixir
def handle_call({:save_pizza, attrs}, _from, state) do
  with {:ok, pizza} <- build_pizza(attrs),
       {:ok, version} <- get_next_version(pizza),
       {:ok, event} <- build_event(pizza, version),
       {:ok, _} <- store_event(event),
       :ok <- publish_event(event) do  # Fire and forget
    {:reply, {:ok, pizza}, state}
  end
end

# Projection processes handle events asynchronously
# If they fall behind, they catch up
# If they fail, they retry
# Commands don't wait for them
```

### 3. **No Event Store Subscription or Catch-Up**
**Severity:** High

**Issue:** Projections can't:
- Start from a checkpoint
- Catch up after being down
- Process events in order
- Handle event processing failures

**Recommendation:** Implement subscription with checkpointing:

```elixir
defmodule Pizza.Infrastructure.Subscription do
  def start_link(opts) do
    projection = Keyword.fetch!(opts, :projection)
    checkpoint_store = Keyword.fetch!(opts, :checkpoint_store)
    
    GenServer.start_link(__MODULE__, {projection, checkpoint_store})
  end
  
  def init({projection, checkpoint_store}) do
    last_position = checkpoint_store.get(projection) || 0
    
    # Start consuming from last checkpoint
    :ok = EventStore.subscribe_from(last_position, self())
    
    {:ok, %{projection: projection, checkpoint_store: checkpoint_store}}
  end
  
  def handle_info({:event, event}, state) do
    case state.projection.handle_event(event) do
      :ok ->
        state.checkpoint_store.save(state.projection, event.version)
        {:noreply, state}
      
      {:error, reason} ->
        # Retry logic
        {:noreply, state}
    end
  end
end
```

---

## Event-Driven Patterns Missing

### 1. **Event Notification**
Notify interested parties when events occur (currently not implemented)

### 2. **Event-Carried State Transfer**
Events contain all necessary data for consumers (partially implemented via CloudEvent data)

### 3. **Event Sourcing** 
Store state as sequence of events (implemented but incomplete - no replay/reconstitution)

### 4. **CQRS (Command Query Responsibility Segregation)**
Separate write model (events) from read model (projection) - architected but not truly separated due to synchronous updates

### 5. **Saga/Process Manager**
Coordinate multi-step processes (not implemented)

### 6. **Event Streaming**
Process events as unbounded stream (not implemented)

---

## Recommended Event-Driven Architecture

### Complete Architecture:

```
┌─────────────────────────────────────────────────────────┐
│                    Commands (Writes)                    │
└───────────────────────┬─────────────────────────────────┘
                        ↓
┌─────────────────────────────────────────────────────────┐
│                 Command Handler                         │
│  1. Load aggregate from events                          │
│  2. Execute command on aggregate                        │
│  3. Persist new events                                  │
│  4. Publish events to bus                               │
└───────────────────────┬─────────────────────────────────┘
                        ↓
                   Event Store
                   (append-only)
                        ↓
                   Event Bus
                        ↓
        ┌───────────────┼───────────────┐
        ↓               ↓               ↓
   Projection 1    Projection 2    Saga/Handler
   (Menu View)     (Analytics)     (Workflows)
        ↓
┌─────────────────────────────────────────────────────────┐
│                    Queries (Reads)                      │
│               Query projections directly                │
└─────────────────────────────────────────────────────────┘
```

### Key Principles:

1. **Commands write events, queries read projections** (CQRS)
2. **Events are facts, immutable and append-only**
3. **Projections react to events asynchronously**
4. **Multiple projections can exist for same events**
5. **Projections can be rebuilt from event history**

---

## Priority Recommendations

**Critical (Breaks Event-Driven Principles):**
1. Implement event publishing mechanism (EventBus)
2. Make projections asynchronous (subscribe to events, don't call directly)
3. Add aggregate reconstitution (load from events, don't query for version)
4. Implement event stream replay for projection rebuilding

**High Priority:**
5. Add specific event types (PizzaCreated, PriceChanged, etc.)
6. Implement event schema versioning and upcasters
7. Add subscription checkpointing for reliable processing
8. Extract generic projection infrastructure

**Medium Priority:**
9. Add event metadata (causation, correlation, actor)
10. Implement retry and dead letter queue for failed events
11. Add monitoring and observability for event processing
12. Document event-driven flows and eventual consistency

**Low Priority:**
13. Consider saga/process manager for multi-step workflows
14. Evaluate external event broker (Kafka, RabbitMQ) for production
15. Add event archival/cleanup strategy
16. Implement event streaming for analytics

---

## Conclusion

The codebase has **event sourcing infrastructure** (event store with versioning) but lacks **event-driven architecture** (asynchronous, decoupled event processing).

**Current state:** Events are stored but projections are updated synchronously - this is a hybrid approach that doesn't realize the benefits of either event sourcing or event-driven architecture.

**Key transformations needed:**

1. **Store events → Publish events** 
   - Add event bus/broker
   - Decouple command side from read side

2. **Synchronous projections → Asynchronous subscriptions**
   - Projections subscribe to events
   - Handle eventual consistency

3. **Query for version → Load from events**
   - Implement aggregate reconstitution
   - True event sourcing pattern

4. **Single event type → Rich event catalog**
   - Specific events for domain operations
   - Enable targeted subscriptions

**Benefits of completing the transformation:**
- True CQRS with independent scaling
- Multiple projections from same events
- Projection rebuilding from event history
- Decoupled components for easier evolution
- Better audit trail and debugging
- Foundation for microservices/distributed systems

The foundation is solid - the event store works well. The next step is to add the "driven" part: making components react to events asynchronously rather than being called synchronously.
