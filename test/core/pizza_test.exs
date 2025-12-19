defmodule Pizza.Core.PizzaTest do
  use ExUnit.Case
  alias Pizza.Events.{PizzaCreated, PriceChanged, PizzaRenamed}
  alias Pizza.Core.Pizza

  describe "pizza creation" do
    test "fails to initialise given required fields not provided at struct initiation" do
      assert_raise ArgumentError, fn ->
        struct!(Pizza, %{})
      end
    end

    test "creates pizza with valid name and price" do
      assert {:ok, %Pizza{name: "Margherita", price: 12.50}, [event]} =
               Pizza.new("Margherita", 12.50)

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
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:ok, updated, [event]} = Pizza.change_price(pizza, 14.0)
      assert updated.price == 14.0
      assert %PriceChanged{old_price: 10.0, new_price: 14.0} = event
    end

    test "allows price decrease" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:ok, updated, [event]} = Pizza.change_price(pizza, 8.0)
      assert updated.price == 8.0
      assert %PriceChanged{old_price: 10.0, new_price: 8.0} = event
    end

    test "rejects excessive price increase" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:error, :price_increase_too_large} = Pizza.change_price(pizza, 20.0)
    end

    test "allows price increase at exactly 50% limit" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:ok, updated, [_event]} = Pizza.change_price(pizza, 15.0)
      assert updated.price == 15.0
    end

    test "returns error for negative price" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:error, :negative_price} == Pizza.change_price(pizza, -5.0)
    end

    test "returns error for zero price" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:error, :negative_price} == Pizza.change_price(pizza, 0)
    end

    test "returns error for non-numeric price" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:error, :invalid_price} == Pizza.change_price(pizza, "expensive")
    end
  end

  describe "renaming" do
    test "allows pizza to be renamed" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:ok, updated, [event]} = Pizza.rename(pizza, "Margherita Supreme")
      assert updated.name == "Margherita Supreme"
      assert %PizzaRenamed{old_name: "Margherita", new_name: "Margherita Supreme"} = event
    end

    test "returns error for empty name" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:error, :empty_name} == Pizza.rename(pizza, "")
    end

    test "returns error for non-string name" do
      {:ok, pizza, _} = Pizza.new("Margherita", 10.0)

      assert {:error, :invalid_name} == Pizza.rename(pizza, 123)
      assert {:error, :invalid_name} == Pizza.rename(pizza, nil)
    end
  end
end
