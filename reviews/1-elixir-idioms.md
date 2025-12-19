# Elixir Idioms Review

## Summary
Overall, the codebase demonstrates good understanding of Elixir fundamentals. However, there are several opportunities to leverage more idiomatic Elixir patterns that would improve clarity, maintainability, and align better with ecosystem conventions.

---

## 🟢 Strengths

### 1. Result Tuples Pattern
Consistently uses `{:ok, value}` / `{:error, reason}` throughout the codebase. This is idiomatic and works well with `with` and `case` expressions.

### 2. Struct Enforcement
Uses `@enforce_keys` appropriately in domain structs (`Pizza`, `CloudEvent`), ensuring critical data is always present.

### 3. Pattern Matching in Function Heads
Good use of pattern matching for dispatch logic (e.g., `Cli.parse/1`, `Dispatcher.list/3`).

### 4. Pipe Operator Usage
Appropriate use of pipes for data transformation sequences, particularly in list processing.

---

## 🟡 Areas for Improvement

### 1. **Case Over Conditional**
**Location:** `lib/core/pizza.ex:9-16`

```elixir
def new(name, price) do
  case price > 0 do
    true ->
      id = get_id()
      {:ok, %__MODULE__{id: id, name: name, price: price}}

    _ ->
      {:error, :negative_price}
  end
end
```

**Issue:** Using `case` with a boolean expression is unidiomatic. This should use `if` or guard clauses.

**Recommendation:**
```elixir
# Option 1: Guard clause (most idiomatic)
def new(name, price) when is_number(price) and price > 0 do
  {:ok, %__MODULE__{id: UUID.uuid4(), name: name, price: price}}
end

def new(_name, _price), do: {:error, :negative_price}

# Option 2: if/else (acceptable if guards aren't suitable)
def new(name, price) do
  if price > 0 do
    {:ok, %__MODULE__{id: UUID.uuid4(), name: name, price: price}}
  else
    {:error, :negative_price}
  end
end
```

### 2. **Inline Variable Assignment in Pipes**
**Location:** `lib/core/pizza.ex:10-11`

```elixir
id = get_id()
{:ok, %__MODULE__{id: id, name: name, price: price}}
```

**Issue:** The `get_id/0` helper is called but not part of a pipeline. Since it's a simple UUID generation, it could be inlined or the helper could be removed entirely.

**Recommendation:**
```elixir
def new(name, price) when is_number(price) and price > 0 do
  {:ok, %__MODULE__{id: UUID.uuid4(), name: name, price: price}}
end
```

### 3. **Redundant Pattern Matching**
**Location:** `lib/adapters/cli.ex:65`

```elixir
defp format_pizza(%Pizza{name: name, price: price}) do
  "#{name} (#{(price)})"
end
```

**Issue:** Double parentheses around `price` are unnecessary. Also, inconsistent with `format_price/1` helper used elsewhere.

**Recommendation:**
```elixir
defp format_pizza(%Pizza{name: name, price: price}) do
  "#{name} (#{format_price(price)})"
end
```

### 4. **Inconsistent Error Tuple Arities**
**Location:** Multiple files

The codebase mixes 2-tuple and 3-tuple error returns:
- `{:error, reason}` - Used in most places
- `{:error, :write_error, message}` - Used in `PizzaProjection`

**Issue:** This inconsistency makes error handling unpredictable. Pick one pattern.

**Recommendation:** Standardize on 2-tuples. If additional context is needed, use structured error terms:
```elixir
{:error, {:write_error, message}}
# or
{:error, %{reason: :write_error, details: message}}
```

### 5. **String Atom Conversion Pattern**
**Location:** `lib/adapters/cli.ex:16-25`

```elixir
defp cast_atom(value) when is_binary(value) do
  lowercase = String.downcase(value)

  try do
    String.to_existing_atom(lowercase)
  rescue
    ArgumentError -> lowercase
  end
end
```

**Issue:** While this prevents atom table pollution (good!), the pattern of falling back to a string is unusual. It would be more explicit to return a tagged tuple.

**Recommendation:**
```elixir
defp cast_atom(value) when is_binary(value) do
  lowercase = String.downcase(value)
  
  case String.to_existing_atom(lowercase) do
    atom when is_atom(atom) -> {:ok, atom}
  rescue
    ArgumentError -> {:error, lowercase}
  end
end

# Or, if you know the valid atoms ahead of time (preferred):
defp cast_list_scope("alphabetical"), do: {:ok, :alphabetical}
defp cast_list_scope("chronological"), do: {:ok, :chronological}
defp cast_list_scope("price"), do: {:ok, :price}
defp cast_list_scope(other), do: {:error, "unknown scope: #{other}"}
```

### 6. **Dynamic Atom Creation in Decoder**
**Location:** `lib/adapters/encoder.ex:36-37`

```elixir
source: String.to_existing_atom(source),
# ...
type: String.to_existing_atom(type),
```

**Issue:** If the source/type atoms don't already exist, this will crash. This is likely intentional (fail fast), but worth documenting or handling more gracefully.

**Recommendation:** Either document this as expected behavior or add validation:
```elixir
with {:ok, source_atom} <- safe_to_existing_atom(source),
     {:ok, type_atom} <- safe_to_existing_atom(type),
     # ... other validations
```

### 7. **Missing `@moduledoc false` or Documentation**
**Location:** Most modules

**Issue:** Per the project guidelines, modules should be "self-documenting." However, modules without `@moduledoc` will generate warnings in mix docs/dialyzer. For internal/private modules, add `@moduledoc false`.

**Recommendation:** Add `@moduledoc false` to adapter implementation modules that aren't part of the public API:
```elixir
defmodule Pizza.Adapters.Encoder do
  @moduledoc false
  # ...
end
```

### 8. **Function Head Redundancy in GenServers**
**Location:** `lib/application/event_store_process.ex`, `lib/application/pizza_projection_process.ex`

```elixir
def store(server, event), do: GenServer.call(server, {:store, event})

def get_event(server, stream_id, version),
  do: GenServer.call(server, {:get_event, stream_id, version})
```

**Issue:** These are simple delegation functions. While they provide a nicer API, there's a lot of boilerplate.

**Recommendation:** This is acceptable as-is for public API clarity. However, if you want to reduce boilerplate, consider using macros or accepting this as the cost of a clean API.

### 9. **Logger Usage Without Application Configuration**
**Location:** Multiple files

```elixir
require Logger
Logger.info("...")
```

**Issue:** Logger is used but `:logger` is in `extra_applications`, not explicitly configured. This is fine, but consider whether structured logging would help.

**Recommendation:** Current usage is acceptable. Consider adding Logger metadata for better tracing:
```elixir
Logger.info("Table created", table: table_name, status: :active)
```

### 10. **Map Access Inconsistency**
**Location:** `lib/adapters/event_store.ex:127`

```elixir
version = Map.get(decoded, "version") || Map.get(decoded, :version)
```

**Issue:** Checking both string and atom keys suggests uncertainty about data shape. This should be normalized earlier.

**Recommendation:** Ensure DynamoDB decoder always returns consistent key types, then access directly:
```elixir
# After ensuring decoder always returns string keys
%{"version" => version} = decoded
```

### 11. **Rescue Without Specific Error**
**Location:** `lib/adapters/event_store.ex:143-145`

```elixir
rescue
  e in ArgumentError ->
    Logger.error("[EventStore] #{Exception.message(e)}")
    {:error, :invalid_aggregate}
```

**Issue:** This is good! Catching specific errors is idiomatic. But ensure this is the only error expected here.

**Recommendation:** Current approach is good. Consider whether other errors need handling.

### 12. **Enum.reduce_while Could Use for Comprehension**
**Location:** `lib/adapters/event_store.ex:24-30`

```elixir
|> Enum.reduce_while(:ok, fn migration, acc ->
  Logger.info("Found migration: #{migration}")

  case perform_migration(store, migration) do
    :ok -> {:cont, acc}
    {:error, :migrations_error} = error -> {:halt, error}
  end
end)
```

**Issue:** This is idiomatic and correct! However, it could be simpler if expressed differently.

**Recommendation:** Current code is fine, but here's an alternative that's more direct:
```elixir
|> Enum.reduce_while(:ok, fn migration, _acc ->
  Logger.info("Found migration: #{migration}")
  
  case perform_migration(store, migration) do
    :ok -> {:cont, :ok}
    error -> {:halt, error}
  end
end)
```

### 13. **Optional Parameters with Defaults**
**Location:** `lib/adapters/pizza_projection.ex:137`

```elixir
defp decode_collection({:ok, %{"Items" => items}}) do
  pizzas =
    items
    |> Enum.map(&ExAws.Dynamo.Decoder.decode/1)
    |> Enum.map(&read_projection/1)
    |> Enum.flat_map(fn
      {:ok, pizza} -> [pizza]
      _ -> []
    end)

  {:ok, pizzas}
end
```

**Issue:** The `flat_map` is clever but makes the intent less clear. The pattern of "filter successful results" is common enough to warrant a clearer approach.

**Recommendation:**
```elixir
defp decode_collection({:ok, %{"Items" => items}}) do
  pizzas =
    items
    |> Enum.map(&ExAws.Dynamo.Decoder.decode/1)
    |> Enum.map(&read_projection/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, pizza} -> pizza end)

  {:ok, pizzas}
end

# Or more concisely with for comprehension:
defp decode_collection({:ok, %{"Items" => items}}) do
  pizzas = 
    for item <- items,
        decoded = ExAws.Dynamo.Decoder.decode(item),
        {:ok, pizza} <- [read_projection(decoded)],
        do: pizza
  
  {:ok, pizzas}
end
```

### 14. **DateTime Handling in CloudEvent**
**Location:** `lib/event/event.ex:31-36`

```elixir
def new_v1(source, type, %DateTime{} = time, data, version)
    when is_integer(version) and version > 0 do
  # ...
end

def new_v1(_source, _type, %DateTime{} = _time, _data, _version) do
  raise ArgumentError, "cloud events require positive integer versions"
end

def new_v1(_source, _type, _time, _data, _version) do
  raise ArgumentError, "cloud events require DateTime timestamps"
end
```

**Issue:** While the guard + raises work, this could be clearer with a single guard that validates both conditions and a single error message.

**Recommendation:**
```elixir
def new_v1(source, type, %DateTime{} = time, data, version)
    when is_integer(version) and version > 0 do
  # ... implementation
end

def new_v1(_source, _type, time, _data, version) do
  cond do
    not is_struct(time, DateTime) ->
      raise ArgumentError, "cloud events require DateTime timestamps, got: #{inspect(time)}"
    
    not (is_integer(version) and version > 0) ->
      raise ArgumentError, "cloud events require positive integer versions, got: #{inspect(version)}"
    
    true ->
      raise ArgumentError, "invalid CloudEvent parameters"
  end
end
```

### 15. **Application Configuration Pattern**
**Location:** `lib/application/event_store_process.ex:22`, similar in other processes

```elixir
event_store_adapter = Keyword.get(opts, :adapter, EventStore)
```

**Issue:** This runtime injection is good for testing, but doesn't follow the compile-time DI pattern mentioned in the project instructions.

**Recommendation:** Consider using `Application.compile_env/3` for adapter configuration:
```elixir
@event_store_adapter Application.compile_env(:pizza, :event_store_adapter, EventStore)

def init(opts) do
  adapter = Keyword.get(opts, :adapter, @event_store_adapter)
  # ...
end
```

---

## 🔴 Issues Requiring Attention

### 1. **Unsafe Atom Creation**
**Location:** `lib/adapters/dynamo.ex:47-52`

```elixir
defp normalize_to_atom(value) do
  value
  |> String.downcase()
  |> String.to_atom()
end
```

**Issue:** This creates atoms dynamically from external input (DynamoDB schema), which can lead to atom table exhaustion. Atoms are never garbage collected.

**Severity:** High - potential DoS vector if malicious table definitions are loaded

**Recommendation:** Use `String.to_existing_atom/1` or a whitelist:
```elixir
defp normalize_to_atom(value) do
  value
  |> String.downcase()
  |> String.to_existing_atom()
rescue
  ArgumentError ->
    # Log warning and return default or error
    Logger.warn("Unexpected DynamoDB type: #{value}")
    :unknown
end
```

### 2. **Inadequate Function Specifications**
**Location:** Throughout the codebase

**Issue:** No `@spec` declarations anywhere. While the project guidelines emphasize self-documenting code, specs help with Dialyzer static analysis and serve as machine-checkable documentation.

**Recommendation:** Add specs to public functions, especially behaviour implementations:
```elixir
@spec new(String.t(), number()) :: {:ok, t()} | {:error, :negative_price}
def new(name, price) when is_number(price) and price > 0 do
  # ...
end
```

### 3. **Missing Input Validation**
**Location:** `lib/core/pizza.ex:6-17`

**Issue:** The `new/2` function doesn't validate that `name` is a non-empty string or that `price` has reasonable bounds.

**Recommendation:**
```elixir
def new(name, price) 
    when is_binary(name) and byte_size(name) > 0 
    and is_number(price) and price > 0 do
  {:ok, %__MODULE__{id: UUID.uuid4(), name: name, price: price}}
end

def new("", _price), do: {:error, :empty_name}
def new(name, _price) when not is_binary(name), do: {:error, :invalid_name}
def new(_name, price) when price <= 0, do: {:error, :negative_price}
def new(_name, price) when not is_number(price), do: {:error, :invalid_price}
```

---

## Testing Idioms

### Minor Issues:
1. **Test descriptions:** `test "should fail to..."` - The "should" is unnecessary in Elixir testing culture. Just state the behavior: `test "fails to initialize when required fields not provided"`

2. **Async tests:** Good use of `async: true` in `encoder_test.exs`. Consider adding this to other independent test modules.

---

## Priority Recommendations

**High Priority:**
1. ~~Fix unsafe atom creation in `Dynamo.normalize_to_atom/1`~~ ✅ FIXED - Removed function, using Map.fetch! instead
2. ~~Standardize error tuple format (2-tuple vs 3-tuple)~~ ✅ FIXED - All Dynamo conversions return {:ok, result} | {:error, {:reason, context}}
3. ~~Add input validation to domain constructors~~ ✅ FIXED - Pizza.new/2 now validates name (non-empty string) and price (positive number) with guards

**Medium Priority:**
4. ~~Replace `case boolean` with guards or `if` statements~~ ✅ FIXED - Pizza.new/2 now uses guard clauses instead of case boolean
5. ~~Add `@moduledoc false` to internal modules~~ ✅ FIXED - Added to all adapter implementation modules
~~6. Consider adding `@spec` for public functions~~

**Low Priority:**
7. ~~Improve clarity of `decode_collection` error handling~~ ✅ FIXED - Replaced flat_map pattern with for comprehension
8. ~~Make Logger calls more structured~~ ✅ FIXED - All Logger calls now use metadata instead of string interpolation
~~9. Consider compile-time DI with `Application.compile_env/3`~~

---

## Conclusion

The codebase shows solid Elixir fundamentals with appropriate use of pattern matching, result tuples, and structs. The main opportunities are around:
- Guard clauses over boolean `case` statements
- Preventing unsafe atom creation
- Standardizing error handling patterns
- Adding validation at domain boundaries

These changes would make the code more idiomatic and robust without requiring major refactoring.
