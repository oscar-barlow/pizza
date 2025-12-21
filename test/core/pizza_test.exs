defmodule Pizza.Core.PizzaTest do
  use ExUnit.Case
  alias Pizza.Events.{PizzaCreated, PriceChanged, PizzaRenamed, PizzaDeleted}
  alias Pizza.Core.Pizza

  describe "pizza creation" do
    test "fails to initialise given required fields not provided at struct initiation" do
      assert_raise ArgumentError, fn ->
        struct!(Pizza, %{})
      end
    end

    test "creates pizza with valid name and price" do
      assert {:ok, [event]} = Pizza.new("Margherita", 12.50)

      assert %PizzaCreated{name: "Margherita", price: 12.50} = event
    end

    test "returns error for negative price" do
      assert {:error, :negative_price} == Pizza.new("Margherita", -1.25)
    end

    test "returns error for zero price" do
      assert {:error, :negative_price} == Pizza.new("Margherita", 0)
    end

    test "returns error for empty name" do
      assert {:error, :empty_name} == Pizza.new("", 12.50)
    end

    test "returns error for non-string name" do
      assert {:error, :invalid_name} == Pizza.new(123, 12.50)
      assert {:error, :invalid_name} == Pizza.new(nil, 12.50)
      assert {:error, :invalid_name} == Pizza.new(:atom, 12.50)
    end

    test "returns error for non-numeric price" do
      assert {:error, :invalid_price} == Pizza.new("Margherita", "expensive")
      assert {:error, :invalid_price} == Pizza.new("Margherita", nil)
    end
  end

  describe "price changes" do
    test "allows reasonable price increase" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:ok, [event]} = Pizza.change_price(pizza, 14.0)
      assert %PriceChanged{old_price: 10.0, new_price: 14.0} = event
    end

    test "allows price decrease" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:ok, [event]} = Pizza.change_price(pizza, 8.0)
      assert %PriceChanged{old_price: 10.0, new_price: 8.0} = event
    end

    test "rejects excessive price increase" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:error, :price_increase_too_large} = Pizza.change_price(pizza, 20.0)
    end

    test "allows price increase at exactly 50% limit" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:ok, [_event]} = Pizza.change_price(pizza, 15.0)
    end

    test "returns error for negative price" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:error, :negative_price} == Pizza.change_price(pizza, -5.0)
    end

    test "returns error for zero price" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:error, :negative_price} == Pizza.change_price(pizza, 0)
    end

    test "returns error for non-numeric price" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:error, :invalid_price} == Pizza.change_price(pizza, "expensive")
    end
  end

  describe "renaming" do
    test "allows pizza to be renamed" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:ok, [event]} = Pizza.rename(pizza, "Margherita Supreme")
      assert %PizzaRenamed{old_name: "Margherita", new_name: "Margherita Supreme"} = event
    end

    test "returns error for empty name" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:error, :empty_name} == Pizza.rename(pizza, "")
    end

    test "returns error for non-string name" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:error, :invalid_name} == Pizza.rename(pizza, 123)
      assert {:error, :invalid_name} == Pizza.rename(pizza, nil)
    end
  end

  describe "deleting pizzas" do
    test "allows pizza to be deleted" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])

      assert {:ok, [event]} = Pizza.delete(pizza)
      assert %PizzaDeleted{} = event
      assert event.pizza_id == pizza.id
    end

    test "prevents price changes on deleted pizzas" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])
      {:ok, [deleted_event]} = Pizza.delete(pizza)
      {:ok, deleted} = Pizza.from_history([created_event, deleted_event])

      assert {:error, :pizza_deleted} = Pizza.change_price(deleted, 12.0)
    end

    test "prevents renaming deleted pizzas" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])
      {:ok, [deleted_event]} = Pizza.delete(pizza)
      {:ok, deleted} = Pizza.from_history([created_event, deleted_event])

      assert {:error, :pizza_deleted} = Pizza.rename(deleted, "New Name")
    end

    test "prevents deleting already deleted pizzas" do
      {:ok, [created_event]} = Pizza.new("Margherita", 10.0)
      {:ok, pizza} = Pizza.from_history([created_event])
      {:ok, [deleted_event]} = Pizza.delete(pizza)
      {:ok, deleted} = Pizza.from_history([created_event, deleted_event])

      assert {:error, :pizza_deleted} = Pizza.delete(deleted)
    end
  end

  describe "reconstituting from event history" do
    test "reconstitutes pizza from single creation event" do
      time = DateTime.utc_now()

      events = [
        %PizzaCreated{
          pizza_id: "pizza-123",
          name: "Margherita",
          price: 10.0,
          occurred_at: time,
          version: 1
        }
      ]

      assert {:ok, pizza} = Pizza.from_history(events)
      assert pizza.id == "pizza-123"
      assert pizza.name == "Margherita"
      assert pizza.price == 10.0
      assert pizza.version == 1
    end

    test "reconstitutes pizza from multiple events" do
      time = DateTime.utc_now()

      events = [
        %PizzaCreated{
          pizza_id: "pizza-456",
          name: "Funghi",
          price: 8.0,
          occurred_at: time,
          version: 1
        },
        %PriceChanged{
          pizza_id: "pizza-456",
          old_price: 8.0,
          new_price: 9.0,
          occurred_at: DateTime.add(time, 60),
          version: 2
        },
        %PizzaRenamed{
          pizza_id: "pizza-456",
          old_name: "Funghi",
          new_name: "Mushroom Deluxe",
          occurred_at: DateTime.add(time, 120),
          version: 3
        }
      ]

      assert {:ok, pizza} = Pizza.from_history(events)
      assert pizza.id == "pizza-456"
      assert pizza.name == "Mushroom Deluxe"
      assert pizza.price == 9.0
      assert pizza.version == 3
    end

    test "reconstitutes pizza with multiple price changes" do
      time = DateTime.utc_now()

      events = [
        %PizzaCreated{
          pizza_id: "pizza-789",
          name: "Quattro Formaggi",
          price: 12.0,
          occurred_at: time,
          version: 1
        },
        %PriceChanged{
          pizza_id: "pizza-789",
          old_price: 12.0,
          new_price: 13.0,
          occurred_at: DateTime.add(time, 60),
          version: 2
        },
        %PriceChanged{
          pizza_id: "pizza-789",
          old_price: 13.0,
          new_price: 14.5,
          occurred_at: DateTime.add(time, 120),
          version: 3
        }
      ]

      assert {:ok, pizza} = Pizza.from_history(events)
      assert pizza.price == 14.5
      assert pizza.version == 3
    end

    test "returns error when event list is empty" do
      assert {:error, :not_found} = Pizza.from_history([])
    end

    test "returns error when PizzaCreated is not the first event" do
      time = DateTime.utc_now()

      events = [
        %PriceChanged{
          pizza_id: "pizza-bad",
          old_price: 10.0,
          new_price: 12.0,
          occurred_at: time,
          version: 1
        }
      ]

      assert {:error, :invalid_history} = Pizza.from_history(events)
    end

    test "returns error when multiple PizzaCreated events exist" do
      time = DateTime.utc_now()

      events = [
        %PizzaCreated{
          pizza_id: "pizza-duplicate",
          name: "First",
          price: 10.0,
          occurred_at: time,
          version: 1
        },
        %PizzaCreated{
          pizza_id: "pizza-duplicate",
          name: "Second",
          price: 12.0,
          occurred_at: DateTime.add(time, 60),
          version: 2
        }
      ]

      assert {:error, :invalid_history} = Pizza.from_history(events)
    end

    test "version comes from events, not calculated during replay" do
      time = DateTime.utc_now()

      events = [
        %PizzaCreated{
          pizza_id: "pizza-version-test",
          name: "Version Test",
          price: 10.0,
          occurred_at: time,
          version: 1
        },
        %PriceChanged{
          pizza_id: "pizza-version-test",
          old_price: 10.0,
          new_price: 12.0,
          occurred_at: DateTime.add(time, 60),
          version: 2
        }
      ]

      {:ok, pizza} = Pizza.from_history(events)

      # Version should be exactly what the event says, not calculated
      assert pizza.version == 2
    end

    test "reconstitutes deleted pizza and enforces invariants" do
      time = DateTime.utc_now()

      events = [
        %PizzaCreated{
          pizza_id: "pizza-deleted",
          name: "Deleted Pizza",
          price: 10.0,
          occurred_at: time,
          version: 1
        },
        %PizzaDeleted{
          pizza_id: "pizza-deleted",
          occurred_at: DateTime.add(time, 60),
          version: 2
        }
      ]

      {:ok, pizza} = Pizza.from_history(events)

      assert pizza.version == 2
      assert {:error, :pizza_deleted} = Pizza.change_price(pizza, 12.0)
      assert {:error, :pizza_deleted} = Pizza.rename(pizza, "New Name")
      assert {:error, :pizza_deleted} = Pizza.delete(pizza)
    end
  end
end
