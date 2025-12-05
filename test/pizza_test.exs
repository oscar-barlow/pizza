defmodule PizzaTest do
  use ExUnit.Case
  doctest Pizza

  test "greets the world" do
    assert Pizza.hello() == :world
  end
end
