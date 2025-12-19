# Consolidated Review: Common Themes & Implementation Plan

## Cross-Review Analysis

### 🎯 Major Themes

#### Theme 1: **Anemic Domain Model** (DDD + EDA)
**Conflict Status:** ❌ Not conflicting - both reviews agree

**DDD Perspective:**
- Pizza is a data structure, not a rich aggregate
- No domain behavior beyond validation at construction
- Missing value objects (Money, PizzaName)
- Domain logic scattered in application layer

**EDA Perspective:**
- Events created in application layer, not by aggregates
- Single generic event type (`:pizza_saved`) lacks semantic meaning
- No domain events that represent business facts

**Shared Solution:**
Enrich Pizza aggregate with:
- Domain operations that produce domain events
- Explicit business rules
- Value objects for price and name
- Events returned from domain operations

---

#### Theme 2: **Synchronous vs Asynchronous Event Processing** (EDA)
**Conflict Status:** ⚠️ Architectural decision needed

**Current State:**
```elixir
# Dispatcher calls projection synchronously
with {:ok, event} <- build_event(...),
     {:ok, _} <- EventStore.store(event),
     {:ok, _} <- PizzaProjection.save(event) do  # Blocks here
```

**Issue:**
- Projection failure prevents command completion
- Can't scale read/write sides independently
- Not truly event-driven
- Defeats CQRS benefits

**Decision Required:**
- **Option A:** Keep synchronous for simplicity (current state)
- **Option B:** Make projections eventually consistent (proper EDA)

**Recommendation:** Option B - but start simple with in-process EventBus

---

#### Theme 3: **Event Identity & Semantics** (DDD + EDA)
**Conflict Status:** ❌ Not conflicting - complementary concerns

**DDD Concern:** Events should represent domain facts with ubiquitous language
- `:pizza_created`, `:price_changed`, `:pizza_added_to_menu`
- Not generic `:pizza_saved`

**EDA Concern:** Events need rich metadata for tracing
- Causation ID (what caused this event)
- Correlation ID (trace across services)
- Event schema versioning

**Shared Solution:**
Define domain events with both semantic meaning AND technical metadata

---

#### Theme 4: **Event Sourcing Implementation** (EDA)
**Conflict Status:** ❌ Not conflicting - implementation gap

**Current Issue:**
- Event store used as database (query for version)
- No aggregate reconstitution from events
- Can't replay events to rebuild projections

**Missing:**
- Load aggregate from event stream
- Apply events to rebuild state
- Stream replay functionality

---

#### Theme 5: **Value Objects vs Primitives** (DDD)
**Conflict Status:** ⚠️ Trade-off decision needed

**DDD Recommendation:**
- Extract Money value object (with Decimal, currency)
- Extract PizzaName value object (validation, trimming)

**Practical Concern:**
- Adds complexity for simple domain
- Serialization overhead
- More boilerplate

**Decision Required:**
- Keep primitives with validation guards?
- Or introduce value objects for richer rules?

**Recommendation:** Start with validated primitives, extract value objects when rules grow complex

---

## Priority Roadmap

### Phase 1: Domain Enrichment (High Value, Foundational) 🎯

**Goal:** Transform Pizza from data structure to rich aggregate

**Changes:**
1. Pizza operations return domain events
   ```elixir
   def new(name, price) -> {:ok, pizza, [%PizzaCreated{}]}
   def change_price(pizza, new_price) -> {:ok, pizza, [%PriceChanged{}]}
   ```

2. Define domain events as structs
   ```elixir
   defmodule Pizza.Core.Events.PizzaCreated
   defmodule Pizza.Core.Events.PriceChanged
   defmodule Pizza.Core.Events.PizzaRenamed
   ```

3. Add domain operations
   - `change_price/2` with validation
   - `rename/2` with validation
   - Business rules as explicit functions

**Dependencies:** None
**Impact:** Foundation for both DDD and EDA improvements
**Effort:** Medium (1-2 days)

---

### Phase 2: Async Event Bus & Projections (High Value) 🚀

**Goal:** Transform synchronous event handling to asynchronous (Phase 1 already publishes events synchronously)

**Changes:**
1. Create simple in-process EventBus
   ```elixir
   defmodule Pizza.Infrastructure.EventBus
     - Registry-based pub/sub
     - subscribe(event_types)
     - publish(event)
   ```

2. Update Dispatcher to publish instead of call
   ```elixir
   with {:ok, _} <- EventStore.store(event),
        :ok <- EventBus.publish(event) do  # Non-blocking
   ```

3. Projections subscribe to events
   ```elixir
   def init(_) do
     EventBus.subscribe([:pizza_created, :price_changed])
   end
   ```

**Dependencies:** Phase 1 (domain events)
**Impact:** Decouples write/read sides, enables multiple projections
**Effort:** Medium (2-3 days)

---

### Phase 3: Explicit Domain Commands (High Value) 💬

**Goal:** Replace generic `:save_pizza` with domain-specific commands

**Why:** Aligns with DDD ubiquitous language principle (Review Point #4)

**Changes:**
1. Define explicit command functions in Dispatcher
   ```elixir
   def create_pizza(name, price)
   def change_pizza_price(pizza_id, new_price)
   def rename_pizza(pizza_id, new_name)
   ```

2. Update handle_call clauses to match commands
   ```elixir
   def handle_call({:create_pizza, name, price}, _from, state)
   def handle_call({:change_price, pizza_id, new_price}, _from, state)
   def handle_call({:rename, pizza_id, new_name}, _from, state)
   ```

3. Route to appropriate Pizza operations
   - `create_pizza` → `Pizza.new/2`
   - `change_price` → `Pizza.load/1` then `Pizza.change_price/2`
   - `rename` → `Pizza.load/1` then `Pizza.rename/2`

**Dependencies:** None (can do now)
**Impact:** More explicit intent, clearer API, prepares for Phase 4
**Effort:** Low (1-2 hours)

---

### Phase 4: Aggregate Reconstitution (High Value) 🎯

**Goal:** Implement proper event sourcing pattern

**Changes:**
1. Add event stream loading
   ```elixir
   EventStore.get_stream(stream_id, from_version)
   ```

2. Implement aggregate loading from events
   ```elixir
   Pizza.load(pizza_id) # Replays events to rebuild state
   ```

3. Remove next_version query, use loaded state
   ```elixir
   {:ok, pizza} = Pizza.load(id)
   {:ok, updated, events} = Pizza.change_price(pizza, new_price)
   persist_events(events, pizza.version + 1)
   ```

**Dependencies:** Phase 1 (domain events with apply logic), Phase 3 (explicit commands)
**Impact:** True event sourcing, enables projection rebuilding
**Effort:** Medium (2-3 days)

---

### Phase 5: Input Validation & Value Objects (Medium Value) 📊

**Goal:** Strengthen domain boundaries

**Changes:**
1. Enhanced validation in Pizza.new/2
   - ✅ Already done: guards for type/range
   - Name length limits
   - Price range validation

2. Optional: Extract value objects if rules grow
   ```elixir
   defmodule Pizza.Core.Money
   defmodule Pizza.Core.PizzaName
   ```

**Dependencies:** None
**Impact:** More robust domain, better error messages
**Effort:** Low (already mostly done)

---

### Phase 6: Event Metadata & Tracing (Medium Value) 📊

**Goal:** Better observability and debugging

**Changes:**
1. Add metadata to CloudEvent
   ```elixir
   causation_id: # What caused this event
   correlation_id: # Trace request flow
   metadata: %{user_id: ..., reason: ...}
   ```

2. Thread correlation IDs through commands
   ```elixir
   Dispatcher.create_pizza(name, price, correlation_id: "req-123")
   ```

**Dependencies:** Phase 2 (event publishing)
**Impact:** Better debugging, tracing, audit logs
**Effort:** Low-Medium (1-2 days)

---

### Phase 7: Projection Infrastructure (Medium Value) 📊

**Goal:** Generic, reusable projection pattern

**Changes:**
1. Extract Projection behaviour
   ```elixir
   @callback handle_event(event, state) :: {:ok, state} | {:error, reason}
   @callback initial_state() :: state
   ```

2. Add checkpointing for reliability
   ```elixir
   checkpoint_store.save(projection_name, last_processed_version)
   ```

3. Retry/DLQ for failures
   ```elixir
   {:error, :retriable, reason} -> schedule_retry()
   {:error, :fatal, reason} -> dead_letter_queue()
   ```

**Dependencies:** Phase 2 (event publishing)
**Impact:** Easy to add new projections, reliable processing
**Effort:** Medium (2-3 days)

---

### Phase 8: Event Schema Versioning (Low-Medium Value) 📈

**Goal:** Handle event evolution over time

**Changes:**
1. Add schema version to events
   ```elixir
   defmodule PizzaCreated do
     @version 2
     defstruct [..., :category] # Added in v2
   ```

2. Implement upcasters
   ```elixir
   def from_map(%{"_version" => 1} = data) do
     # Transform v1 -> v2
   end
   ```

**Dependencies:** Phase 1 (domain events)
**Impact:** Future-proof event schema changes
**Effort:** Medium (2 days)

---

## Conflict Resolution

### 1. **Value Objects vs Primitives**

**Decision:** ✅ Validated primitives with guards (keep current approach)

**Rationale:**
- Current domain is simple
- Guards provide type safety
- Can extract later without breaking changes
- Avoids premature complexity

**Future trigger:**
- If we add currency support → Money value object
- If name has complex rules → PizzaName value object
- If we need Money arithmetic → definitely value object

---

### 2. **Synchronous vs Async Projections**

**Decision:** ⏸️ **DEFERRED** - Keep synchronous for now, async as final phase

**Rationale:**
- Async adds significant complexity (EventBus, subscriptions, eventual consistency)
- Current synchronous approach works and is testable
- Foundation work (domain events, reconstitution) provides value independently
- Can move to async once other improvements are stable

**Migration path:**
- Complete Phases 1, 3, 4, 5, 7 first
- Phase 2 (Event Publishing) becomes final phase
- Phase 6 (Projection Infrastructure) happens after Phase 2

---

### 3. **Domain Events in Core vs Application**

**Decision:** Domain produces events (Phase 1)

**Rationale:**
- DDD: Events are domain concepts
- EDA: Rich event types enable subscriptions
- Better testability
- Clearer intent

**No conflict - both reviews agree**

---

## Implementation Order

### Revised Sequence (Async Deferred):

```
Phase 1: Domain Enrichment ✅ COMPLETE
   ↓
Phase 3: Explicit Domain Commands ✅ COMPLETE
   ↓
Phase 4: Aggregate Reconstitution
   ↓
Phase 5: Input Validation (mostly complete)
   ↓
Phase 6: Event Metadata
   ↓
Phase 8: Event Versioning
   ↓
Phase 2: Async Event Bus (FINAL - if desired)
   ↓
Phase 7: Projection Infrastructure (after Phase 2)
```

### Rationale for Reordering:

- **Phase 1 COMPLETE:** Domain produces events, foundation established
- **Phase 3 NEW:** Explicit commands before reconstitution - needed for update operations
- **Phase 4 second:** True event sourcing pattern, high value
- **Phase 5 mostly done:** Already completed in previous work
- **Phase 6 & 8:** Improve event quality without async complexity
- **Phase 2 & 7 last:** Async transformation as final step (optional)

### Parallelization Opportunities:

- Phase 4 continues throughout (ongoing refinement)
- Phase 5 can overlap with Phase 3
- Phase 7 independent of Phase 3/5

---

## High-Value Quick Wins ⚡

1. **Define domain events** (Phase 1, Day 1)
   - Immediate: Better semantics
   - Foundation for everything else

2. **Add event publishing** (Phase 2, Days 2-3)
   - Immediate: Decoupled architecture
   - Enables async processing

3. **Pizza operations return events** (Phase 1, Day 2)
   - Immediate: Domain logic in domain
   - Testable without infrastructure

---

## What NOT to Do (Anti-Patterns to Avoid)

❌ **Don't:** Keep synchronous projection calls
✅ **Do:** Async event publishing

❌ **Don't:** Query event store for version on every write
✅ **Do:** Load aggregate from events

❌ **Don't:** Generic `:pizza_saved` event
✅ **Do:** Specific event types (`:pizza_created`, `:price_changed`)

❌ **Don't:** Create events in Dispatcher
✅ **Do:** Aggregates produce events

❌ **Don't:** Generic `:save_pizza` command
✅ **Do:** Explicit commands (`:create_pizza`, `:change_price`, `:rename`)

❌ **Don't:** Add complexity without clear benefit
✅ **Do:** Start simple, add patterns as needed

---

## Success Metrics

### After Phase 1-3:
- [ ] Pizza aggregate has 3+ operations that return events
- [ ] Domain events defined as explicit structs
- [ ] Projections subscribe to events (not called directly)
- [ ] Aggregate can be loaded from event stream
- [ ] Can rebuild projection from events

### After Phase 4-7:
- [ ] Generic projection behaviour for reuse
- [ ] Checkpointing implemented
- [ ] Event metadata for tracing
- [ ] Event versioning strategy documented
- [ ] New projection can be added in < 50 LOC

---

## Open Questions

1. **External Event Broker?**
   - Current: In-process EventBus
   - Future: Kafka/RabbitMQ for production?
   - Decision point: When scaling beyond single node

2. **Saga/Process Manager?**
   - Current: Not needed (simple domain)
   - Future: If multi-step workflows emerge
   - Decision point: When adding Orders/Fulfillment

3. **Snapshot Support?**
   - Current: Not needed (few events per aggregate)
   - Future: If event streams grow large
   - Decision point: When aggregate reconstruction is slow

4. **CQRS Read Model Tech?**
   - Current: DynamoDB projection
   - Future: Different tech for different queries? (ElasticSearch, Redis)
   - Decision point: When query patterns diverge

---

## Estimated Total Effort

### Core Phases (Synchronous Architecture):
- **Phase 1:** 1-2 days (domain enrichment)
- **Phase 3:** 2-3 days (aggregate reconstitution)
- **Phase 4:** 0.5 days (validation - mostly done)
- **Phase 5:** 1-2 days (event metadata)
- **Phase 7:** 2 days (event versioning)

**Core Total:** 6.5-9.5 days of focused work
**Realistic timeline with testing/refinement:** 2-2.5 weeks

### Optional Async Phases (Deferred):
- **Phase 2:** 2-3 days (event publishing)
- **Phase 6:** 2-3 days (projection infrastructure)

**With Async:** +4-6 days (additional 1.5-2 weeks)
