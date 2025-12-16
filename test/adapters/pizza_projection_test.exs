defmodule Pizza.Adapters.PizzaProjectionTest do
  use ExUnit.Case

  alias Pizza.Adapters.{EventStore, PizzaProjection}
  alias Pizza.Core.Pizza, as: CorePizza
  alias Pizza.Event.CloudEvent

  setup do
    event_store = EventStore.default()
    pizza_projection = PizzaProjection.default()
    Test.RepositoryHelper.clear_tables()

    with {:ok, pizza} <- CorePizza.new("margherita", 7.5) do
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
       event_store: event_store,
       pizza_projection: pizza_projection,
       pizza: pizza,
       cloud_event: cloud_event,
       time: time}
    end
  end

  describe "saving pizza" do

    test "given a cloud event, saves a pizza", %{cloud_event: cloud_event, pizza_projection: pizza_projection, pizza: pizza} do
      {:ok, id} = PizzaProjection.save(pizza_projection, cloud_event)

      {:ok, retrieved_pizza} = PizzaProjection.get(pizza_projection, id)
      assert retrieved_pizza == pizza

    end

    test "does not overwrite a pizza given event has already been received" do
      assert false
    end

    test "updates a pizza" do
      assert false
    end

  end

  describe "retriving a list of all pizzas" do

    test "retrieves all pizzas, sorted alphabetically" do
      assert false
    end

    test "retrieves all pizzas, sorted by updated time" do
      assert false
    end

    test "retrieves all pizzas, sorted by price" do
      assert false
    end

  end

  describe "deleting a pizza" do
    test "deletes a pizza" do
      assert false
    end
  end
end
