defmodule Pizza.Adapters.PizzaProjectionTest do
  use ExUnit.Case

  alias Pizza.Adapters.PizzaProjection
  alias Pizza.Core.Pizza, as: CorePizza
  alias Pizza.Event.CloudEvent

  setup_all do
    pizza_projection = PizzaProjection.default()

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
       pizza_projection: pizza_projection, pizza: pizza, cloud_event: cloud_event, time: time}
    end
  end

  describe "saving pizza" do
    setup %{cloud_event: cloud_event, pizza_projection: pizza_projection} do
      Test.RepositoryHelper.clear_tables()
      PizzaProjection.save(pizza_projection, cloud_event)
      :ok
    end

    test "given a cloud event, saves a pizza", %{pizza_projection: pizza_projection, pizza: pizza} do
      {:ok, retrieved_pizza} = PizzaProjection.get(pizza_projection, pizza.id)
      assert retrieved_pizza == pizza
    end

    test "does not overwrite a pizza, even if data have changed, given event version has already been received",
         %{cloud_event: cloud_event, pizza_projection: pizza_projection, pizza: pizza} do
      changed = %CorePizza{
        id: pizza.id,
        name: String.reverse(pizza.name),
        price: pizza.price * 2
      }

      changed_cloud_event =
        CloudEvent.new_v1(
          :test,
          :create_pizza,
          cloud_event.time,
          changed,
          1
        )

      assert {:error, :write_error,
              "Attempted to overwrite pizza with id #{pizza.id} and version #{cloud_event.version}: {\"ConditionalCheckFailedException\", \"The conditional request failed\"}"} ==
               PizzaProjection.save(pizza_projection, changed_cloud_event)
    end

    test "updates a pizza", %{
      cloud_event: cloud_event,
      pizza_projection: pizza_projection,
      pizza: pizza
    } do
      changed = %CorePizza{
        id: pizza.id,
        name: pizza.name,
        price: 10
      }

      changed_cloud_event =
        CloudEvent.new_v1(
          :test,
          :create_pizza,
          cloud_event.time,
          changed,
          2
        )

      {:ok, id} = PizzaProjection.save(pizza_projection, changed_cloud_event)

      {:ok, retrieved_pizza} = PizzaProjection.get(pizza_projection, id)
      assert retrieved_pizza == changed
    end
  end

  describe "retriving a list of all pizzas" do
    setup %{pizza_projection: pizza_projection, cloud_event: cloud_event, time: time} do
      Test.RepositoryHelper.clear_tables()
      PizzaProjection.save(pizza_projection, cloud_event)

      {:ok, funghi} = CorePizza.new("funghi", 8)

      funghi_event =
        CloudEvent.new_v1(
          :test,
          :create_pizza,
          DateTime.shift(time, minute: 1),
          funghi,
          1
        )

      {:ok, pepperoni} = CorePizza.new("pepperoni", 10)

      pepperoni_event =
        CloudEvent.new_v1(
          :test,
          :create_pizza,
          DateTime.shift(time, minute: 2),
          pepperoni,
          1
        )

      Enum.each([cloud_event, funghi_event, pepperoni_event], fn event ->
        PizzaProjection.save(pizza_projection, event)
      end)

      {:ok, funghi: funghi, pepperoni: pepperoni}
    end

    test "retrieves all pizzas, sorted ascending alphabetically", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, alphabetical_ascending} = PizzaProjection.list_alphabetical(pizza_projection, :asc)

      assert alphabetical_ascending == [funghi, pizza, pepperoni]
    end

    test "retrieves all pizzas, sorted descending alphabetically", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, alphabetical_descending} = PizzaProjection.list_alphabetical(pizza_projection, :desc)

      assert alphabetical_descending == [pepperoni, pizza, funghi]
    end

    test "retrieves all pizzas, sorted ascending by updated time", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, time_ascending} = PizzaProjection.list_chronological(pizza_projection, :asc)
      assert time_ascending == [pizza, funghi, pepperoni]
    end

    test "retrieves all pizzas, sorted descending by updated time", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, time_descending} = PizzaProjection.list_chronological(pizza_projection, :desc)
      assert time_descending == [pepperoni, funghi, pizza]
    end

    test "retrieves all pizzas, sorted ascending by price", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, price_ascending} = PizzaProjection.list_by_price(pizza_projection, :asc)
      assert price_ascending == [pizza, funghi, pepperoni]
    end

    test "retrieves all pizzas, sorted descending by price", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, price_descnding} = PizzaProjection.list_by_price(pizza_projection, :desc)
      assert price_descnding == [pepperoni, funghi, pizza]
    end
  end

  describe "deleting a pizza" do
    setup %{cloud_event: cloud_event, pizza_projection: pizza_projection} do
      Test.RepositoryHelper.clear_tables()
      PizzaProjection.save(pizza_projection, cloud_event)
      :ok
    end

    test "deletes a pizza", %{pizza_projection: pizza_projection, pizza: pizza} do
      PizzaProjection.delete(pizza_projection, pizza.id)

      assert {:error, :not_found} == PizzaProjection.get(pizza_projection, pizza.id)
    end
  end
end
