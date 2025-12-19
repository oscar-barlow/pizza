# Hexagonal Architecture Review

## Summary
The codebase demonstrates strong adherence to hexagonal (ports and adapters) principles with clear separation between core domain, ports (interfaces), and adapters (implementations). The dependency direction is correct, and the architecture enables testability and flexibility. However, there are opportunities to strengthen boundaries and clarify layer responsibilities.

---

## 🟢 Strengths

### 1. Clear Dependency Direction
**Core → Ports → Adapters** dependency flow is correct:
- `Pizza.Core.Pizza` has no dependencies on infrastructure
- Adapters (`Pizza.Adapters.*`) depend on and implement port behaviours
- Domain is isolated and pure

### 2. Port Definitions as Behaviours
**Location:** `lib/ports/ports.ex`

Port contracts are defined as Elixir behaviours with `@callback`, making the interface explicit and compile-time checkable.

```elixir
defmodule Pizza.Ports.EventStore do
  @callback migrate(term()) :: :ok | {:error, :migrations_error}
  @callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
  # ...
end
```

### 3. Adapter Implementation
Adapters properly implement port behaviours with `@behaviour` declarations:

```elixir
defmodule Pizza.Adapters.EventStore do
  @behaviour Pizza.Ports.EventStore
  # ...
end
```

### 4. Multiple Adapters for Same Port
The architecture allows (and tests demonstrate) swapping implementations:
- `EventStoreProcess` can use different adapters via `:adapter` option
- Tests can inject mock implementations
- Production uses real DynamoDB adapters

### 5. Application Layer Orchestration
**Location:** `lib/application/dispatcher.ex`

The application layer coordinates adapters without business logic, acting as a proper orchestrator.

---

## 🟡 Areas for Improvement

### 1. **Port Location and Naming**
**Location:** `lib/ports/ports.ex`

**Issue:** All ports are defined in a single file under a namespace module. This works but doesn't scale well and makes the structure less discoverable.

**Current:**
```elixir
defmodule Pizza.Ports do
  defmodule Cli do
    @callback parse(list(String.t())) :: {:ok, command()} | {:error, String.t()}
  end
  
  defmodule EventStore do
    @callback migrate(term()) :: :ok | {:error, :migrations_error}
  end
end
```

**Recommendation:** Split into separate files for better organization:
```
lib/ports/
  cli.ex           # Pizza.Ports.Cli
  event_store.ex   # Pizza.Ports.EventStore
  pizza_projection.ex # Pizza.Ports.PizzaProjection
```

```elixir
# lib/ports/event_store.ex
defmodule Pizza.Ports.EventStore do
  @moduledoc """
  Port for event storage operations.
  Implementations must provide event persistence with versioning.
  """
  
  alias Pizza.Event.CloudEvent
  
  @callback migrate(term()) :: :ok | {:error, :migrations_error}
  @callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
  # ...
end
```

### 2. **Leaky Abstractions in Port Definitions**
**Location:** `lib/ports/ports.ex:22-30`

```elixir
defmodule EventStore do
  @type config :: term()

  @callback migrate(term()) :: :ok | {:error, :migrations_error}
  @callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
  # ...
end
```

**Issues:**
- Port callbacks accept `term()` as first parameter (the store instance)
- This exposes implementation details - why does the port need a "config" or "instance"?
- The port should define WHAT operations are available, not HOW they're implemented

**Recommendation:** Two approaches:

**Option A: Stateless Port (Preferred for this codebase)**
```elixir
defmodule Pizza.Ports.EventStore do
  @callback store(CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
  @callback get_event(String.t(), pos_integer()) :: {:ok, CloudEvent.t()} | {:error, atom()}
  @callback next_version(term()) :: {:ok, pos_integer()} | {:error, term()}
end

# Adapter wraps configuration
defmodule Pizza.Adapters.DynamoEventStore do
  @behaviour Pizza.Ports.EventStore
  
  @impl true
  def store(event) do
    config = get_config() # Adapter responsibility
    do_store(config, event)
  end
end
```

**Option B: Explicit Configuration Type**
```elixir
defmodule Pizza.Ports.EventStore do
  @type config :: %{client: module(), table: String.t()}
  
  @callback store(config(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
end
```

### 3. **Application Layer as Adapter Wrapper**
**Location:** `lib/application/event_store_process.ex`, `lib/application/pizza_projection_process.ex`

**Issue:** These GenServers are thin wrappers around adapters. They don't add business value, just provide process boundary.

```elixir
defmodule Pizza.Application.EventStoreProcess do
  def store(server, event), do: GenServer.call(server, {:store, event})
  
  def handle_call({:store, %CloudEvent{} = event}, _from, state) do
    %{event_store_adapter: adapter, client: client} = state
    {:reply, adapter.store(client, event), state}
  end
end
```

**This is actually good hexagonal architecture!** The process provides:
- Process isolation
- Supervision tree integration
- Potential for async/concurrent operations

**However:** The naming suggests they're part of "application layer" when they're really **secondary adapters** (driving the domain).

**Recommendation:** Clarify their role:

**Option 1: Rename to reflect adapter nature**
```
lib/adapters/
  event_store_adapter.ex  # GenServer wrapper
  dynamo_event_store.ex   # DynamoDB implementation
```

**Option 2: Keep but document as infrastructure**
```elixir
# lib/infrastructure/event_store_process.ex
defmodule Pizza.Infrastructure.EventStoreProcess do
  @moduledoc """
  Process adapter providing concurrent access to event store.
  Acts as a secondary adapter in hexagonal architecture.
  """
end
```

### 4. **Mixed Responsibilities in Dispatcher**
**Location:** `lib/application/dispatcher.ex:43-75`

**Issue:** Dispatcher handles both:
- Application orchestration (coordinating adapters)
- Domain knowledge (building pizzas, creating events)

```elixir
defp build_pizza(%{name: name, price: price}) do
  Pizza.new(name, price)
end

defp build_event(%Pizza{} = pizza, clock, version) do
  event = CloudEvent.new_v1(:pizza_app, :pizza_saved, clock.(), pizza, version)
  {:ok, event}
end
```

**Issue:** The dispatcher knows too much about domain construction. This is application layer bleeding into domain concerns.

**Recommendation:** Move domain knowledge to domain:

```elixir
# lib/application/dispatcher.ex
def handle_call({:save_pizza, attrs}, _from, state) do
  with {:ok, pizza, events} <- Pizza.create(attrs),  # Domain returns events
       {:ok, version} <- EventStoreProcess.next_version(state.event_store, pizza),
       :ok <- persist_events(events, version, state) do
    {:reply, {:ok, pizza}, state}
  else
    {:error, reason} -> {:reply, {:error, reason}, state}
  end
end

defp persist_events(events, base_version, state) do
  events
  |> Enum.with_index(base_version)
  |> Enum.reduce_while(:ok, fn {event, version}, _acc ->
    cloud_event = wrap_in_cloud_event(event, version)
    case EventStoreProcess.store(state.event_store, cloud_event) do
      {:ok, _} -> {:cont, :ok}
      error -> {:halt, error}
    end
  end)
end
```

### 5. **CloudEvent as Infrastructure Concern**
**Location:** `lib/event/event.ex`

**Issue:** `CloudEvent` is in neither core domain nor adapters - it's in a separate `event/` folder. But CloudEvents are an infrastructure format (following cloudevents.io spec), not a domain concept.

**Current Structure:**
```
lib/
  core/          # Domain
  event/         # Where does this belong?
  adapters/      # Infrastructure
```

**Recommendation:** Either:

**Option A: Move to adapters (if it's purely infrastructure)**
```
lib/adapters/cloud_event.ex  # CloudEvent is serialization format
```

**Option B: Split domain events from transport format**
```
lib/core/events/
  pizza_created.ex      # Domain event
  
lib/adapters/
  cloud_event_mapper.ex # Maps domain events → CloudEvent format
```

This aligns with DDD: domain events are domain concepts, their serialization is infrastructure.

### 6. **Port Type Specifications Too Generic**
**Location:** `lib/ports/ports.ex`

**Issue:** Type specs use `term()` extensively, reducing type safety:

```elixir
@callback next_version(term(), term()) :: {:ok, pos_integer()} | {:error, term()}
```

**Recommendation:** Use specific types:

```elixir
defmodule Pizza.Ports.EventStore do
  alias Pizza.Event.CloudEvent
  
  @type aggregate :: struct()
  @type error_reason :: :invalid_aggregate | :read_error | :write_error
  
  @callback next_version(aggregate()) :: {:ok, pos_integer()} | {:error, error_reason()}
  @callback store(CloudEvent.t()) :: {:ok, String.t()} | {:error, error_reason()}
end
```

### 7. **Inconsistent Error Handling Across Ports**
**Issue:** Different ports return different error shapes:

- `EventStore.store/2` → `{:error, :write_error}` (2-tuple)
- `PizzaProjection.save/2` → `{:error, :write_error, String.t()}` (3-tuple)
- `EventStore.get_event/3` → `{:error, :not_found | :read_error}` (union)

**Recommendation:** Standardize error returns across all ports:

```elixir
# Option 1: Consistent 2-tuple with structured errors
@type error :: 
  {:write_error, details :: String.t()} |
  {:read_error, details :: String.t()} |
  :not_found |
  :invalid_version

@callback store(CloudEvent.t()) :: {:ok, String.t()} | {:error, error()}

# Option 2: Always include details
@callback store(CloudEvent.t()) :: 
  {:ok, String.t()} | 
  {:error, reason :: atom(), details :: String.t()}
```

### 8. **CLI as Both Primary and Secondary Adapter**
**Location:** `lib/adapters/cli.ex`

**Issue:** CLI is implementing `Pizza.Ports.Cli` which defines both:
- Input parsing (primary adapter - drives the application)
- Output formatting (secondary adapter - driven by application)

```elixir
defmodule Pizza.Ports.Cli do
  @callback parse(list(String.t())) :: {:ok, command()} | {:error, String.t()}
  @callback format(result(), command()) :: String.t()
end
```

**This violates single responsibility.** A port should represent one direction of dependency.

**Recommendation:** Split into two ports:

```elixir
# lib/ports/command_parser.ex
defmodule Pizza.Ports.CommandParser do
  @moduledoc "Primary port: external input → application"
  
  @callback parse(list(String.t())) :: {:ok, command()} | {:error, String.t()}
end

# lib/ports/output_formatter.ex
defmodule Pizza.Ports.OutputFormatter do
  @moduledoc "Secondary port: application → external output"
  
  @callback format(result(), context :: term()) :: String.t()
end

# lib/adapters/cli_parser.ex
defmodule Pizza.Adapters.CliParser do
  @behaviour Pizza.Ports.CommandParser
  # parse implementation
end

# lib/adapters/cli_formatter.ex
defmodule Pizza.Adapters.CliFormatter do
  @behaviour Pizza.Ports.OutputFormatter
  # format implementation
end
```

### 9. **Missing Primary Port Abstraction**
**Issue:** The application layer (`Dispatcher`) is called directly by `Pizza.Application.main/1`:

```elixir
# lib/application/application.ex
defp dispatch({:save, attrs}), do: Dispatcher.save_pizza(attrs)
defp dispatch({:list, scope, order}), do: Dispatcher.list_pizzas(scope, order)
```

**This is acceptable** but could be more explicit about primary ports.

**Recommendation:** Make primary port explicit:

```elixir
# lib/ports/pizza_use_cases.ex
defmodule Pizza.Ports.PizzaUseCases do
  @moduledoc "Primary port: defines application use cases"
  
  @callback add_pizza(name :: String.t(), price :: float()) :: 
    {:ok, Pizza.t()} | {:error, term()}
  
  @callback list_pizzas(sort_by :: atom(), order :: atom()) :: 
    {:ok, list(Pizza.t())} | {:error, term()}
end

# lib/application/pizza_use_cases.ex
defmodule Pizza.Application.PizzaUseCases do
  @behaviour Pizza.Ports.PizzaUseCases
  
  @impl true
  def add_pizza(name, price) do
    Dispatcher.save_pizza(%{name: name, price: price})
  end
  
  @impl true
  def list_pizzas(sort_by, order) do
    Dispatcher.list_pizzas(sort_by, order)
  end
end
```

This makes it explicit that the application exposes use cases as a primary port.

---

## 🔴 Critical Issues

### 1. **Encoder Module Breaks Layer Boundaries**
**Location:** `lib/adapters/encoder.ex`

**Issue:** `Encoder` is in the adapters layer but handles two very different concerns:
1. Converting `CloudEvent` ↔ DynamoDB format (adapter concern)
2. Converting `Pizza` ↔ serialized format (domain serialization)

```elixir
def encode(%Pizza{id: id, name: name, price: price}) do
  %{"id" => id, "name" => name, "price" => price}
end

defp decode(%{"id" => id, "name" => name, "price" => price}) do
  {:ok, %Pizza{id: id, name: name, price: price}}
end
```

**The problem:** 
- The adapter knows the internal structure of `Pizza`
- It constructs domain objects directly
- If `Pizza` structure changes, the adapter must change

**Severity:** High - violates open/closed principle and creates coupling

**Recommendation:** Move domain serialization to domain:

```elixir
# lib/core/pizza.ex
defmodule Pizza.Core.Pizza do
  def from_map(%{"id" => id, "name" => name, "price" => price}) do
    # Domain owns its deserialization
    {:ok, %__MODULE__{id: id, name: name, price: price}}
  end
  
  def to_map(%__MODULE__{id: id, name: name, price: price}) do
    %{"id" => id, "name" => name, "price" => price}
  end
end

# lib/adapters/encoder.ex - only handles CloudEvent format
defmodule Pizza.Adapters.CloudEventEncoder do
  def encode(%CloudEvent{data: data} = event) do
    %{
      "stream_id" => event.stream_id,
      "data" => data.to_map(data),  # Delegate to domain
      # ...
    }
  end
end
```

### 2. **Ports Accept Infrastructure Types**
**Location:** `lib/ports/ports.ex:20`

```elixir
@callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
```

**Issue:** The port accepts `CloudEvent.t()` which is an infrastructure type. Ports should use domain types or be agnostic to format.

**Severity:** Medium - creates coupling between port definition and infrastructure format

**Recommendation:** 

**Option A: Port uses domain events**
```elixir
defmodule Pizza.Ports.EventStore do
  @callback store(domain_event :: struct()) :: {:ok, event_id :: String.t()} | {:error, term()}
end

# Adapter handles conversion
defmodule Pizza.Adapters.DynamoEventStore do
  def store(domain_event) do
    cloud_event = CloudEventMapper.from_domain_event(domain_event)
    persist_cloud_event(cloud_event)
  end
end
```

**Option B: Accept generic event format**
```elixir
@callback store(event_data :: map()) :: {:ok, String.t()} | {:error, term()}
```

### 3. **Process Modules Coupling Application to Infrastructure**
**Location:** `lib/application/dispatcher.ex:6-7`

```elixir
alias Pizza.Application.EventStoreProcess
alias Pizza.Application.PizzaProjectionProcess
```

**Issue:** The application layer knows about specific process implementations. It should depend on abstractions (ports), not concretions.

**Current flow:**
```
Dispatcher → EventStoreProcess → EventStore adapter
            (concrete)          (abstract)
```

**Better flow:**
```
Dispatcher → EventStore port → EventStoreProcess (adapter)
            (abstract)         (concrete)
```

**Recommendation:** Use port abstractions:

```elixir
# lib/application/dispatcher.ex
defmodule Pizza.Application.Dispatcher do
  @event_store Application.compile_env(:pizza, :event_store, Pizza.Adapters.EventStore)
  @projection Application.compile_env(:pizza, :pizza_projection, Pizza.Adapters.PizzaProjection)
  
  def init(opts) do
    event_store = Keyword.get(opts, :event_store, @event_store)
    pizza_projection = Keyword.get(opts, :pizza_projection, @projection)
    
    state = %{
      event_store: event_store,
      pizza_projection: pizza_projection,
      clock: Keyword.get(opts, :clock, &DateTime.utc_now/0)
    }
    
    {:ok, state}
  end
  
  def handle_call({:save_pizza, attrs}, _from, state) do
    with {:ok, pizza} <- build_pizza(attrs),
         {:ok, version} <- state.event_store.next_version(pizza),
         # ...
  end
end
```

---

## Architecture Diagram

Current architecture (simplified):

```
┌─────────────────────────────────────────────────┐
│                  Primary Adapters               │
│  (CLI, Future: HTTP API, Message Consumer)      │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│            Application Layer                    │
│  (Dispatcher, Process Wrappers)                 │
│  - Orchestrates use cases                       │
│  - Coordinates adapters                         │
└────────────┬────────────────────┬────────────────┘
             │                    │
             ▼                    ▼
      ┌───────────┐         ┌──────────┐
      │  Ports    │         │  Core    │
      │           │◄────────│  Domain  │
      │           │         │          │
      └─────┬─────┘         └──────────┘
            │
            ▼
┌─────────────────────────────────────────────────┐
│            Secondary Adapters                   │
│  (DynamoDB, Future: PostgreSQL, Kafka)          │
└─────────────────────────────────────────────────┘
```

**Dependency Rule:** Arrows point inward (dependencies flow toward domain)

---

## Testing Alignment with Hexagonal Architecture

### Strengths:
1. **Adapter tests use real dependencies** (DynamoDB via LocalStack)
2. **Application layer can inject mocks** via init options
3. **Domain tests are isolated** (no infrastructure)

### Improvements:

```elixir
# Test using different adapter implementation
test "saves pizza through in-memory adapter" do
  {:ok, dispatcher} = Dispatcher.start_link(
    event_store: InMemoryEventStore,
    pizza_projection: InMemoryProjection
  )
  
  assert {:ok, pizza} = Dispatcher.save_pizza(dispatcher, %{name: "Test", price: 10})
end
```

---

## Priority Recommendations

**High Priority:**
1. Fix `Encoder` boundary violation - move domain serialization to domain
2. Standardize error handling across all ports
3. Make port type signatures more specific (remove `term()`)
4. Split CLI port into input/output ports

**Medium Priority:**
5. Reorganize ports into separate files
6. Clarify role of process wrappers (adapters vs infrastructure)
7. Remove `CloudEvent` from port signatures
8. Use port abstractions instead of concrete processes

**Low Priority:**
9. Extract primary port interface for use cases
10. Document hexagonal layers explicitly
11. Consider splitting domain events from transport format

---

## Conclusion

The codebase demonstrates **strong hexagonal architecture fundamentals**:
- ✅ Correct dependency direction (inward toward domain)
- ✅ Clear port/adapter separation
- ✅ Behaviour-based contracts
- ✅ Testable with swappable implementations

**Key improvements:**
- **Strengthen boundaries:** Remove domain knowledge from adapters
- **Clarify layers:** Better organize ports, separate concerns
- **Type safety:** Make port contracts more specific
- **Consistency:** Standardize error handling across ports

The architecture is sound and provides a solid foundation. The recommended changes would make the boundaries more explicit and reduce coupling between layers.
