defmodule Pizza.Core.PizzaTest do
  use ExUnit.Case
  alias Pizza.Core.Pizza

  describe "pizza" do
    test "should fail to initialise given required fields not provided at struct initiation" do
      assert_raise ArgumentError, fn ->
        struct!(Pizza, %{})
      end
    end

    test "should blow given struct initiated with negative price" do
      assert {:error, :negative_price} == Pizza.new("example-name", -1.25)
    end
  end
end
