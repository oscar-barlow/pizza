defmodule Pizza.Adapters.PizzaProjectionRepository do
  @behaviour Pizza.Ports.PizzaProjectionRepository

  alias Pizza.Core.Pizza

  def get_pizza(id) do
    %Pizza{id: id, name: "pizza", price: 1}
  end

  def list_pizzas() do
    [Pizza.new("pizza", 1)]
  end
end
