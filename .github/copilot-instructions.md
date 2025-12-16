# AI Agent Instructions for Pizza

## Architecture: Ports and Adapters (Hexagonal)

This codebase follows a strict hexagonal/ports-and-adapters pattern:

- **Core Domain** (`lib/pizza/core/`): Business logic with no external dependencies
  - Pure domain logic with no framework or infrastructure concerns

- **Ports** (`lib/pizza/ports/`): Behaviour definitions for adapters
  - Defines contracts for external interfaces
  - Future: Database, HTTP, CLI ports as needed

- **Adapters** (`lib/pizza/adapters/`): External interface implementations
  - Implements port behaviours using `@behaviour`
  - Uses compile-time dependency injection via `Application.compile_env/3`

**Critical Pattern**: Core domain never imports adapters. Adapters import and use core domain.

## Dependency Injection via Application Config

Adapters use **compile-time DI** for testability:

```elixir
@module Application.compile_env(:pizza, :dependency_key, Pizza.Core.DefaultImpl)
```

- **Production**: Defaults to real implementations
- **Test**: `config/test.exs` overrides with test mocks
- Mocks defined in `test/test_helper.exs` using `Mox.defmock/2`

## Testing Conventions

1. **TDD Workflow**: This project follows test-driven development - write tests before implementation

2. **Mox for Behaviour Mocking**:
   - Define behaviours with `@callback` in core modules
   - Create mocks: `Mox.defmock(MockModule, for: Pizza.Core.SomeBehaviour)`
   - Always call `:verify_on_exit!` in test setup
   - Use `expect/3` or `stub/3` for mock expectations

3. **Test Organization**:
   - Mirror `lib/` structure in `test/`
   - Unit tests for core domain should NOT use mocks
   - Adapter tests SHOULD mock their dependencies
  - Prefer natural-language `describe` block titles instead of function/arity signatures

## Key Commands

- **Run tests**: `mix test`
- **Run single test file**: `mix test test/path/to/file_test.exs`
- **Compile**: `mix compile`
- **Run in console**: `iex -S mix` (for REPL experimentation)

## Design Decisions & Constraints

1. **Readability Over Cleverness**: Prioritize clear, straightforward code. If a pipeline or abstraction makes the logic harder to follow, break it down.

2. **Self-Documenting Code**: Code should be clear enough to be self-documenting. Do NOT add `@doc` or `@moduledoc` to most modules - the code itself should explain its purpose through good naming and structure. This is counter to standard Elixir conventions but preferred for this codebase. Only add documentation for truly complex algorithms or non-obvious behavior.

3. **Error Handling**: Domain operations return result tuples instead of raising exceptions
   - Success: `{:ok, result}`
   - Failure: `{:error, :reason_atom}`
   - Use `with` expressions for chaining operations that can fail
   - Adapters map domain errors to user-friendly messages

4. **Invariant Enforcement**: Domain modules act as consistency boundaries
   - Validate business rules before state changes
   - Return error tuples for validation failures

## Common Patterns

- **Result tuples for error handling**:
  ```elixir
  case SomeModule.some_operation(data) do
    {:ok, result} -> {:ok, result, "Success message"}
    {:error, :some_reason} -> {:error, "Error message"}
  end
  ```

- **`with` expressions for chaining operations**:
  ```elixir
  with {:ok, step1} <- operation_one(data),
       {:ok, step2} <- operation_two(step1) do
    {:ok, step2, "Success"}
  else
    {:error, reason} -> {:error, format_error(reason)}
  end
  ```

- **Pipe into `then/2`** for struct creation:
  ```elixir
  data
  |> transform()
  |> then(fn result -> %SomeStruct{field: result} end)
  ```

- **Pattern match in function heads** for type safety:
  ```elixir
  def some_function(%SomeStruct{} = struct, %OtherStruct{} = other)
  ```

- **Alias at module level**, not inline usage
