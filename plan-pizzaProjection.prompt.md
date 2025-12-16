Plan for pizza projection implementation:

- Create a new DynamoDB migration JSON (for example `priv/migrations/V1_2__create_pizza_projection_table.json`) that defines a table keyed by pizza id. Ensure the event repository migration pipeline runs both migrations.
- Extend `Pizza.Ports.PizzaProjection` with `save_pizza/1` and any other needed callbacks (for example `update_pizza/1`) while keeping the core domain decoupled from adapters.
- Test-drive a real projection adapter in `lib/adapters/pizza_projection.ex` that persists pizzas via `ExAws.Dynamo`; write adapter tests exercising create, update, get, and list operations, clearing the table between runs.
- Implement orchestration in an application-level module (e.g. `Pizza.App`) with lightweight processes: one for storing events, one for the projection, and a dispatcher (probably `GenServer`-based) to forward “pizza saved” messages. Supervise these processes under `Pizza.Application` while keeping the CLI synchronous.
- Revisit the CLI adapter once persistence exists, ensuring it writes events, triggers projection updates, and handles errors gracefully.
