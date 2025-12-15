defmodule Pizza.Adapters.EventStoreTest do
  use ExUnit.Case

  alias Pizza.Adapters.EventStore
  alias Pizza.Event.CloudEvent
  alias Pizza.Core.Pizza

  setup do
    event_store = EventStore.default()
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

      {:ok,
       event_store: event_store, pizza: pizza, cloud_event: cloud_event, time: time}
    end
  end

  test "should store a pizza creation event", %{
    event_store: event_store,
    cloud_event: cloud_event
  } do
    assert {:ok, stored_id} = EventStore.store(event_store, cloud_event)
    assert stored_id == cloud_event.id

    assert {:ok, fetched_event} =
             EventStore.get_event(event_store, cloud_event.stream_id, cloud_event.version)

    assert fetched_event == cloud_event
  end
end
