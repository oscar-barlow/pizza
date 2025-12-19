# Domain-Driven Design Review

## Summary
The codebase demonstrates some DDD principles but lacks key domain modeling concepts. The current implementation treats `Pizza` as a simple data structure rather than a rich domain entity with business rules, lifecycle, and behavior. There's minimal domain language, no clear bounded contexts, and missing strategic patterns.

---

## 🟢 Strengths

### 1. Invariant Protection at Construction
`Pizza.new/2` validates business rules (positive price) at creation time, preventing invalid states.

### 2. Separation of Concerns
The code separates domain (`Pizza.Core.Pizza`) from infrastructure (`Pizza.Adapters.*`), showing awareness of DDD's onion architecture concept.

### 3. Event Naming
Events use business-meaningful names (`:pizza_saved`) rather than technical terms, showing domain language awareness.

---

## 🟡 Areas for Improvement

### 1. **Anemic Domain Model**
**Location:** `lib/core/pizza.ex`

```elixir
defmodule Pizza.Core.Pizza do
  @enforce_keys [:id, :name, :price]
  defstruct id: nil, name: nil, price: nil

  def new(name, price) do
    # validation only
  end
end
```

**Issue:** `Pizza` is a data structure with one factory function. It has no behavior, no lifecycle methods, no business operations. This is an **anemic domain model** - one of the most common DDD anti-patterns.

**What's Missing:**
- Domain operations (e.g., `change_price/2`, `rename/2`)
- Business rule enforcement beyond construction
- Domain events as first-class concepts within the aggregate
- Value objects for price/name if they have rules

**Recommendation:** Enrich the domain model with behavior:

```elixir
defmodule Pizza.Core.Pizza do
  @enforce_keys [:id, :name, :price]
  defstruct id: nil, name: nil, price: nil

  @type t :: %__MODULE__{
    id: String.t(),
    name: Name.t(),
    price: Money.t()
  }

  # Factory
  def new(name, price) when is_binary(name) and is_number(price) and price > 0 do
    with {:ok, name} <- Name.new(name),
         {:ok, price} <- Money.new(price) do
      pizza = %__MODULE__{
        id: UUID.uuid4(),
        name: name,
        price: price
      }
      {:ok, pizza, [:pizza_created]}
    end
  end

  # Domain operations
  def change_price(%__MODULE__{} = pizza, new_price) do
    with {:ok, price} <- Money.new(new_price),
         :ok <- validate_price_change(pizza.price, price) do
      updated = %{pizza | price: price}
      {:ok, updated, [:price_changed]}
    end
  end

  def rename(%__MODULE__{} = pizza, new_name) do
    with {:ok, name} <- Name.new(new_name) do
      updated = %{pizza | name: name}
      {:ok, updated, [:pizza_renamed]}
    end
  end

  defp validate_price_change(old_price, new_price) do
    # Business rule: price changes can't exceed 50% at once
    max_change = Money.multiply(old_price, 1.5)
    if Money.less_than?(new_price, max_change) do
      :ok
    else
      {:error, :price_change_too_large}
    end
  end
end
```

### 2. **Missing Value Objects**
**Location:** Throughout

**Issue:** Primitive types (`String.t()`, `float()`) are used directly. DDD recommends value objects to encapsulate validation and domain concepts.

**Examples:**
- `name` should be a `PizzaName` value object with validation (length, allowed characters)
- `price` should be a `Money` value object with currency, rounding rules
- `version` in events should be a `Version` or `SequenceNumber` value object

**Recommendation:**
```elixir
defmodule Pizza.Core.Money do
  @enforce_keys [:amount, :currency]
  defstruct [:amount, :currency]

  @type t :: %__MODULE__{amount: Decimal.t(), currency: atom()}

  def new(amount, currency \\ :USD) when is_number(amount) and amount > 0 do
    {:ok, %__MODULE__{
      amount: Decimal.new(amount),
      currency: currency
    }}
  end

  def new(amount, _) when amount <= 0, do: {:error, :negative_amount}
  def new(_, _), do: {:error, :invalid_amount}

  def less_than?(%__MODULE__{} = a, %__MODULE__{} = b) do
    # Ensure same currency, compare amounts
  end
end

defmodule Pizza.Core.PizzaName do
  @enforce_keys [:value]
  defstruct [:value]

  @max_length 50

  def new(value) when is_binary(value) do
    trimmed = String.trim(value)
    
    cond do
      byte_size(trimmed) == 0 -> {:error, :empty_name}
      byte_size(trimmed) > @max_length -> {:error, :name_too_long}
      true -> {:ok, %__MODULE__{value: trimmed}}
    end
  end
end
```

### 3. **No Aggregate Boundaries**
**Issue:** There's only one aggregate (`Pizza`), which is appropriate for this simple domain. However, there's no clear thinking about:
- What constitutes an aggregate boundary?
- What if we add `Topping`, `Order`, `Customer`? How would they relate?
- Transaction boundaries aren't explicit

**Recommendation:** Document aggregate design decisions:
```elixir
# lib/core/pizza.ex
# Aggregate Root: Pizza
# 
# Boundaries:
# - Pizza is a self-contained aggregate with no child entities
# - Each pizza has independent lifecycle
# - Pizza changes are atomic (single event stream)
#
# Business Invariants:
# - Price must be positive
# - Name must not be empty
# - Price changes limited to 50% at once
```

### 4. **Missing Ubiquitous Language**
**Issue:** The codebase doesn't demonstrate rich domain language. Terms like "save", "get", "list" are CRUD operations, not domain operations.

**Current:** `Dispatcher.save_pizza(attrs)`
**Better:** `PizzaMenu.add_to_menu(pizza_specification)`

**Current:** `:pizza_saved` event
**Better:** `:pizza_added_to_menu`, `:pizza_priced`, `:pizza_created`

**Recommendation:** Develop richer vocabulary:
- "Menu" instead of "projection"
- "Pricing" as a domain concept
- "Available", "Unavailable" states
- "Special", "Regular" as pizza types

### 5. **Domain Logic in Application Layer**
**Location:** `lib/application/dispatcher.ex:43-69`

```elixir
defp build_pizza(%{name: name, price: price}) do
  Pizza.new(name, price)
end

defp build_event(%Pizza{} = pizza, clock, version) do
  event = CloudEvent.new_v1(:pizza_app, :pizza_saved, clock.(), pizza, version)
  {:ok, event}
end
```

**Issue:** The dispatcher orchestrates but also knows about event construction details. Domain events should be produced by the aggregate itself.

**Recommendation:** Move event creation to domain:
```elixir
# In Pizza module
def new(name, price) do
  pizza = %__MODULE__{id: UUID.uuid4(), name: name, price: price}
  event = %PizzaCreated{
    pizza_id: pizza.id,
    name: name,
    price: price,
    occurred_at: DateTime.utc_now()
  }
  {:ok, pizza, [event]}
end

# In Dispatcher
defp save_pizza(attrs) do
  with {:ok, pizza, events} <- Pizza.new(attrs.name, attrs.price),
       {:ok, version} <- get_version(pizza),
       {:ok, _} <- persist_events(events, version) do
    {:ok, pizza}
  end
end
```

### 6. **Event Sourcing vs DDD Confusion**
**Issue:** The codebase uses event sourcing (storing events in `EventStore`) but treats events as infrastructure, not domain concepts. Events are created in the application layer, not by aggregates.

**Recommendation:** 
- Domain aggregates should produce domain events
- Events should represent domain facts, not technical operations
- Consider: `PizzaCreated`, `PriceChanged`, `PizzaAddedToMenu`

```elixir
defmodule Pizza.Core.Events do
  defmodule PizzaCreated do
    @enforce_keys [:pizza_id, :name, :price, :occurred_at]
    defstruct [:pizza_id, :name, :price, :occurred_at]
  end

  defmodule PriceChanged do
    @enforce_keys [:pizza_id, :old_price, :new_price, :occurred_at]
    defstruct [:pizza_id, :old_price, :new_price, :occurred_at]
  end
end
```

### 7. **Missing Domain Services**
**Issue:** No domain services for complex operations that don't naturally fit in a single aggregate.

**Example Scenarios:**
- Pricing strategy (seasonal pricing, bulk discounts)
- Menu curation (selecting which pizzas appear)
- Pizza comparison/recommendation

**Recommendation:** Introduce domain services when needed:
```elixir
defmodule Pizza.Core.PricingService do
  # Domain service for complex pricing logic
  
  def calculate_seasonal_price(%Pizza{} = pizza, season) do
    base_price = pizza.price
    multiplier = seasonal_multiplier(season)
    
    Money.multiply(base_price, multiplier)
  end
  
  defp seasonal_multiplier(:summer), do: 1.1
  defp seasonal_multiplier(:winter), do: 0.9
  defp seasonal_multiplier(_), do: 1.0
end
```

### 8. **No Bounded Contexts**
**Issue:** For a simple pizza app, this might be overkill, but there's no thinking about how the domain might be divided into contexts.

**Potential Contexts:**
- **Menu Management** (adding/removing pizzas, pricing)
- **Ordering** (customer orders, order fulfillment)
- **Inventory** (ingredients, stock management)

**Recommendation:** Even if not implementing multiple contexts now, document the domain model:
```markdown
## Bounded Contexts

### Menu Context
Responsible for: Pizza definitions, pricing, availability
Entities: Pizza (aggregate root)
Events: PizzaCreated, PriceChanged, PizzaDiscontinued

### (Future) Ordering Context
Would handle: Customer orders, order lifecycle
Would integrate with Menu via: Pizza catalog, pricing queries
```

---

## 🔴 Critical Issues

### 1. **No Business Rules Beyond Construction**
**Severity:** High

**Issue:** The only business rule enforced is "price > 0" at creation. Real domains have many rules:
- Can prices be changed? By how much? By whom?
- Can pizzas be discontinued?
- Are there limits on name length?
- What happens when a pizza is out of stock?

**Impact:** The domain model can't express business logic, forcing it into application or adapter layers.

**Recommendation:** Identify and implement business rules:
```elixir
defmodule Pizza.Core.Pizza do
  # Business rules as explicit functions
  
  def can_change_price?(%__MODULE__{} = pizza, _user_role) do
    # Rule: Only managers can change prices of established pizzas
    # For now, simplified version:
    {:ok, true}
  end
  
  def validate_price_change(%__MODULE__{price: current}, new_price) do
    max_increase = Money.multiply(current, 1.5)
    
    cond do
      Money.less_than_or_equal?(new_price, Money.zero()) ->
        {:error, :price_must_be_positive}
      
      Money.greater_than?(new_price, max_increase) ->
        {:error, :price_increase_too_large}
      
      true ->
        :ok
    end
  end
end
```

### 2. **Aggregate Doesn't Own Its ID**
**Location:** `lib/core/pizza.ex:11`, `lib/event/event.ex:52-57`

```elixir
# Pizza generates its own ID
id = get_id()

# But CloudEvent also generates stream_id FROM pizza
def stream_id_for(%{id: id} = data) do
  aggregate_prefix = ...
  "#{aggregate_prefix}-#{id}"
end
```

**Issue:** The aggregate identity is constructed in two places. The stream ID pattern is infrastructure concern leaking into the domain.

**Recommendation:** Let the aggregate own all aspects of its identity:
```elixir
defmodule Pizza.Core.Pizza do
  def new(name, price) do
    id = PizzaId.generate()
    # ...
  end
  
  def stream_id(%__MODULE__{id: id}) do
    "pizza-#{id}"
  end
end
```

### 3. **No Lifecycle States**
**Issue:** Pizzas have no state beyond their data. Real pizzas might be:
- Draft
- Available
- Discontinued
- Seasonal

**Recommendation:** Add lifecycle states if they represent business rules:
```elixir
defmodule Pizza.Core.Pizza do
  @type status :: :draft | :available | :discontinued
  
  defstruct [:id, :name, :price, :status]
  
  def publish(%__MODULE__{status: :draft} = pizza) do
    {:ok, %{pizza | status: :available}, [:pizza_published]}
  end
  
  def publish(%__MODULE__{status: status}) do
    {:error, :already_published}
  end
end
```

---

## Testing from DDD Perspective

### Issues:

1. **Tests focus on persistence, not domain rules**
   - `pizza_projection_test.exs` tests CRUD operations
   - Missing: tests for business rule enforcement
   - Missing: tests for invalid state transitions

2. **No specification tests**
   - Should test business scenarios, not technical operations
   - Example: "Cannot increase price by more than 50% at once"

**Recommendation:**
```elixir
describe "price changes" do
  test "allows price increase within limit" do
    {:ok, pizza} = Pizza.new("Margherita", 10.0)
    
    assert {:ok, updated, events} = Pizza.change_price(pizza, 14.0)
    assert updated.price == Money.new(14.0)
    assert :price_changed in events
  end
  
  test "rejects excessive price increase" do
    {:ok, pizza} = Pizza.new("Margherita", 10.0)
    
    assert {:error, :price_increase_too_large} = 
      Pizza.change_price(pizza, 20.0)
  end
end
```

---

## Strategic DDD Patterns (Future Considerations)

For a more complex pizza domain, consider:

### 1. **Shared Kernel**
If you had multiple teams/services, what would be shared?
- Pizza identity concept
- Money value object
- Common events

### 2. **Anti-Corruption Layer**
When integrating with external systems:
- Payment gateway (transform payment concepts)
- Delivery service (map addresses, statuses)

### 3. **Context Mapping**
Document relationships between contexts:
- Menu → Ordering (published language via events)
- Ordering → Inventory (partnership)

---

## Priority Recommendations

**High Priority:**
1. Enrich `Pizza` with domain behavior (not just data)
2. Extract value objects for `Money` and `PizzaName`
3. Move event creation into domain aggregates
4. Add business rule validation beyond construction

**Medium Priority:**
5. Define and document aggregate boundaries
6. Develop ubiquitous language (rename CRUD operations)
7. Add lifecycle states if they represent business rules
8. Introduce domain services for complex operations

**Low Priority:**
9. Document bounded contexts (even if not implemented)
10. Consider strategic patterns for future growth
11. Add specification tests for business rules

---

## Conclusion

The codebase shows awareness of hexagonal architecture and event sourcing, but **lacks the heart of DDD: a rich domain model**. The current `Pizza` is a data structure, not an aggregate root with behavior, business rules, and domain events.

Key improvements:
- **Enrich the model:** Add behavior, not just data
- **Value objects:** Encapsulate primitive types with rules
- **Domain events:** Let aggregates produce events
- **Business rules:** Make rules explicit in domain code
- **Ubiquitous language:** Use business terms, not CRUD

The good news: the architecture supports these improvements. The hexagonal structure provides a solid foundation for introducing richer domain modeling without disrupting the adapters.
