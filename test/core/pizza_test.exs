defmodule Pizza.Core.PizzaTest do
  use ExUnit.Case
  alias Pizza.Core.Pizza

  describe "pizza creation" do
    test "fails to initialise given required fields not provided at struct initiation" do
      assert_raise ArgumentError, fn ->
        struct!(Pizza, %{})
      end
    end

    test "creates pizza with valid name and price" do
      assert {:ok, %Pizza{name: "Margherita", price: 12.50}} = Pizza.new("Margherita", 12.50)
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
end
