defmodule Pizza.Adapters.EventRepositoryTest do
  use ExUnit.Case

  alias Pizza.Adapters.EventRepository
  alias Pizza.Event.PizzaEvent
  alias Pizza.Core.Pizza

  setup do
    event_repository = EventRepository.default()
    EventRepository.migrate(event_repository)
    Test.RepositoryHelper.clear_tables()

    with {:ok, pizza} <- Pizza.new("margherita", 7.5) do
      pizza_event =
        PizzaEvent.new_with_id_and_timestamp(
          :test,
          "1.0",
          :create_pizza,
          pizza
        )
        {:ok, event_repository: event_repository, pizza_event: pizza_event}
    end
  end

  test "should store a pizza creation event", %{
    event_repository: event_repository,
    pizza_event: pizza_event
  } do
    EventRepository.store(event_repository, pizza_event)

    # assert pizza events table contains 1 item
    EventRepository.get_event(event_repository, pizza_event.id)
  end
end
