defmodule Pizza.Adapters.EventRepositoryTest do
  use ExUnit.Case

  alias Pizza.Adapters.EventRepository
  alias Pizza.Event.CloudEvent
  alias Pizza.Core.Pizza

  setup do
    event_repository = EventRepository.default()
    EventRepository.migrate(event_repository)
    Test.RepositoryHelper.clear_tables()

    with {:ok, pizza} <- Pizza.new("margherita", 7.5) do
      time = DateTime.utc_now()
      cloud_event =
        CloudEvent.new_v1(
          :test,
          :create_pizza,
          time,
          pizza,
          1
        )
        {:ok, event_repository: event_repository, pizza: pizza, cloud_event: cloud_event, time: time}
    end
  end

  test "should store a pizza creation event", %{
    event_repository: event_repository,
    pizza: pizza,
    cloud_event: cloud_event,
    time: time
  } do
    EventRepository.store(event_repository, cloud_event)

    event = EventRepository.get_event(event_repository, cloud_event.id)
    assert event == %CloudEvent{
      id: "pizza-#{pizza.id}",
      stream_id: "pizza-#{pizza.id}",
      version: 1,
      source: :test,
      specversion: "1.0",
      type: :create_pizza,
      time: time,
      data: pizza
    }
  end
end
