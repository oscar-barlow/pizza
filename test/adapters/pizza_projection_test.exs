defmodule Pizza.Adapters.PizzaProjectionTest do
  use ExUnit.Case

  alias Pizza.Adapters.PizzaProjection
  alias Pizza.Event.CloudEvent
  alias Pizza.Events.{PizzaCreated, PriceChanged}

  setup_all do
    pizza_projection = PizzaProjection.default()

    {:ok, pizza, _events} = Pizza.Core.Pizza.new("margherita", 7.5)
    time = DateTime.utc_now()

    pizza_created_event = %PizzaCreated{
      pizza_id: pizza.id,
      name: pizza.name,
      price: pizza.price,
      occurred_at: time
    }

    cloud_event =
      CloudEvent.new_v1(:test, :pizza_created, time, pizza_created_event, 1)

    {:ok,
     pizza_projection: pizza_projection,
     pizza: pizza,
     cloud_event: cloud_event,
     time: time}
  end

  describe "saving pizza" do
    setup %{cloud_event: cloud_event, pizza_projection: pizza_projection} do
      Test.RepositoryHelper.clear_tables()
      PizzaProjection.save(pizza_projection, cloud_event)
      :ok
    end

    test "given a cloud event, saves a pizza", %{pizza_projection: pizza_projection, pizza: pizza} do
      {:ok, retrieved_pizza} = PizzaProjection.get(pizza_projection, pizza.id)
      assert retrieved_pizza == with_version(pizza, 1)
    end

    test "does not overwrite a pizza, even if data have changed, given event version has already been received",
         %{cloud_event: cloud_event, pizza_projection: pizza_projection, pizza: pizza} do
      changed_event = %PizzaCreated{
        pizza_id: pizza.id,
        name: String.reverse(pizza.name),
        price: pizza.price * 2,
        occurred_at: cloud_event.time
      }

      changed_cloud_event =
        CloudEvent.new_v1(:test, :pizza_created, cloud_event.time, changed_event, 1)

      assert {:error, :write_error,
              "Attempted to overwrite pizza with id #{pizza.id} and version #{cloud_event.version}: {\"ConditionalCheckFailedException\", \"The conditional request failed\"}"} ==
               PizzaProjection.save(pizza_projection, changed_cloud_event)
    end

    test "updates a pizza", %{
      cloud_event: cloud_event,
      pizza_projection: pizza_projection,
      pizza: pizza
    } do
      changed_cloud_event =
        price_changed_cloud_event(
          pizza.id,
          pizza.price,
          10,
          DateTime.shift(cloud_event.time, minute: 1),
          2
        )

      {:ok, id} = PizzaProjection.save(pizza_projection, changed_cloud_event)

      {:ok, retrieved_pizza} = PizzaProjection.get(pizza_projection, id)
      expected = %Pizza.Core.Pizza{id: pizza.id, name: pizza.name, price: 10, version: 2}
      assert retrieved_pizza == expected
    end
  end

  describe "retriving a list of all pizzas" do
    setup %{pizza_projection: pizza_projection, cloud_event: cloud_event, time: time} do
      Test.RepositoryHelper.clear_tables()
      PizzaProjection.save(pizza_projection, cloud_event)

      {:ok, funghi, _events} = Pizza.Core.Pizza.new("funghi", 8)

      funghi_event =
        pizza_created_cloud_event(funghi, DateTime.shift(time, minute: 1), 1)

      {:ok, pepperoni, _events} = Pizza.Core.Pizza.new("pepperoni", 10)

      pepperoni_event =
        pizza_created_cloud_event(pepperoni, DateTime.shift(time, minute: 2), 1)

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

      assert alphabetical_ascending == [with_version(funghi, 1), with_version(pizza, 1), with_version(pepperoni, 1)]
    end

    test "retrieves all pizzas, sorted descending alphabetically", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, alphabetical_descending} = PizzaProjection.list_alphabetical(pizza_projection, :desc)

      assert alphabetical_descending == [with_version(pepperoni, 1), with_version(pizza, 1), with_version(funghi, 1)]
    end

    test "retrieves all pizzas, sorted ascending by updated time", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, time_ascending} = PizzaProjection.list_chronological(pizza_projection, :asc)
      assert time_ascending == [with_version(pizza, 1), with_version(funghi, 1), with_version(pepperoni, 1)]
    end

    test "retrieves all pizzas, sorted descending by updated time", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, time_descending} = PizzaProjection.list_chronological(pizza_projection, :desc)
      assert time_descending == [with_version(pepperoni, 1), with_version(funghi, 1), with_version(pizza, 1)]
    end

    test "retrieves all pizzas, sorted ascending by price", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, price_ascending} = PizzaProjection.list_by_price(pizza_projection, :asc)
      assert price_ascending == [with_version(pizza, 1), with_version(funghi, 1), with_version(pepperoni, 1)]
    end

    test "retrieves all pizzas, sorted descending by price", %{
      pizza_projection: pizza_projection,
      pizza: pizza,
      funghi: funghi,
      pepperoni: pepperoni
    } do
      {:ok, price_descnding} = PizzaProjection.list_by_price(pizza_projection, :desc)
      assert price_descnding == [with_version(pepperoni, 1), with_version(funghi, 1), with_version(pizza, 1)]
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

  defp with_version(%Pizza.Core.Pizza{} = pizza, version), do: %{pizza | version: version}

  defp pizza_created_cloud_event(pizza, time, version) do
    %PizzaCreated{
      pizza_id: pizza.id,
      name: pizza.name,
      price: pizza.price,
      occurred_at: time
    }
    |> then(&CloudEvent.new_v1(:test, :pizza_created, time, &1, version))
  end

  defp price_changed_cloud_event(pizza_id, old_price, new_price, time, version) do
    %PriceChanged{
      pizza_id: pizza_id,
      old_price: old_price,
      new_price: new_price,
      occurred_at: time
    }
    |> then(&CloudEvent.new_v1(:test, :price_changed, time, &1, version))
  end
end
