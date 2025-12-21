defmodule Pizza.Application.DispatcherProjectionTest do
  use ExUnit.Case

  alias Pizza.Adapters.PizzaProjection
  alias Pizza.Application.Dispatcher
  alias Pizza.Application.EventStoreProcess
  alias Pizza.Application.PizzaProjectionProcess

  setup_all do
    Test.RepositoryHelper.ensure_tables!()
    :ok
  end

  setup do
    Test.RepositoryHelper.clear_tables()

    {:ok, event_store} = EventStoreProcess.start_link(name: :"event_store_#{inspect(self())}")

    {:ok, pizza_projection} =
      PizzaProjectionProcess.start_link(name: :"pizza_projection_#{inspect(self())}")

    {:ok, dispatcher} =
      Dispatcher.start_link(
        event_store: event_store,
        pizza_projection: pizza_projection,
        name: :"dispatcher_#{inspect(self())}"
      )

    {:ok,
     event_store: event_store,
     pizza_projection: pizza_projection,
     dispatcher: dispatcher}
  end

  test "reads projection after create without waiting", %{dispatcher: dispatcher} do
    Enum.each(1..10, fn index ->
      {:ok, pizza_id} = Dispatcher.create_pizza(dispatcher, "Pizza #{index}", index + 5.0)

      Test.Eventually.eventually(fn ->
        assert {:ok, pizza} = PizzaProjection.get(PizzaProjection.default(), pizza_id)
        assert pizza.id == pizza_id
      end)
    end)
  end
end
