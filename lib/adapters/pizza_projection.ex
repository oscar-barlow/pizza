defmodule Pizza.Adapters.PizzaProjection do
  @behaviour Pizza.Ports.PizzaProjection

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  @pizza_projection_table "pizza_projection"

  alias Pizza.Core.Pizza

  def default() do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def get_pizza(id) do
    Pizza.new("pizza", 1)
  end

  @impl true
  def list_pizzas() do
    [Pizza.new("pizza", 1)]
  end
end
