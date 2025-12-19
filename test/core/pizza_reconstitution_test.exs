defmodule Pizza.Core.PizzaReconstitutionTest do
  use ExUnit.Case, async: true

  alias Pizza.Application.Dispatcher
  alias Pizza.Application.EventStoreProcess
  alias Pizza.Application.PizzaProjectionProcess
  alias Pizza.Core.Pizza

  setup_all do
    Test.RepositoryHelper.ensure_tables!()
    :ok
  end

  setup do
    Test.RepositoryHelper.clear_tables()

    {:ok, event_store} = EventStoreProcess.start_link(name: :"event_store_#{inspect(self())}")

    {:ok, pizza_projection} =
      PizzaProjectionProcess.start_link(name: :"pizza_projection_#{inspect(self())}")

    {:ok, event_store: event_store, pizza_projection: pizza_projection}
  end

  describe "aggregate reconstitution" do
    test "reconstitutes pizza from single creation event", %{
      event_store: event_store,
      pizza_projection: pizza_projection
    } do
      {:ok, dispatcher} =
        Dispatcher.start_link(
          event_store: event_store,
          pizza_projection: pizza_projection,
          name: :"dispatcher_#{inspect(self())}"
        )

      {:ok, created_pizza} = Dispatcher.create_pizza(dispatcher, "Margherita", 10.0)

      assert {:ok, events} = domain_events_for(event_store, created_pizza.id)
      assert {:ok, loaded_pizza} = Pizza.from_history(events)

      assert loaded_pizza.id == created_pizza.id
      assert loaded_pizza.name == "Margherita"
      assert loaded_pizza.price == 10.0
      assert loaded_pizza.version == 1
    end

    test "reconstitutes pizza from multiple events", %{
      event_store: event_store,
      pizza_projection: pizza_projection
    } do
      {:ok, dispatcher} =
        Dispatcher.start_link(
          event_store: event_store,
          pizza_projection: pizza_projection,
          name: :"dispatcher_#{inspect(self())}"
        )

      {:ok, created_pizza} = Dispatcher.create_pizza(dispatcher, "Funghi", 8.0)
      {:ok, _} = Dispatcher.change_pizza_price(dispatcher, created_pizza.id, 9.0)
      {:ok, _} = Dispatcher.rename_pizza(dispatcher, created_pizza.id, "Mushroom Special")

      assert {:ok, events} = domain_events_for(event_store, created_pizza.id)
      assert {:ok, loaded_pizza} = Pizza.from_history(events)

      assert loaded_pizza.id == created_pizza.id
      assert loaded_pizza.name == "Mushroom Special"
      assert loaded_pizza.price == 9.0
      assert loaded_pizza.version == 3
    end

    test "returns error when no events found", %{event_store: event_store} do
      assert {:ok, events} = domain_events_for(event_store, "nonexistent-id")
      assert {:error, :not_found} = Pizza.from_history(events)
    end
  end

  defp domain_events_for(event_store, pizza_id) do
    stream_id = "pizza-#{pizza_id}"

    with {:ok, cloud_events} <- EventStoreProcess.get_stream(event_store, stream_id) do
      {:ok, Enum.map(cloud_events, & &1.data)}
    end
  end
end
