defmodule Pizza.Ports do
  alias Pizza.Core.Pizza

  defmodule Cli do
    @callback parse(command: list(String.t())) ::
                {:ok, Pizza.t() | list(Pizza.t())} | {:error, String.t()}
  end

  defmodule EventRepository do
    @type config :: term()

    @callback migrate(term()) :: :ok | {:error, :migrations_error}
    @callback store(term(), Pizza.t()) :: {:ok, Pizza.t()} | {:error, :write_error, String.t()}
  end

  defmodule PizzaProjectionRepository do
    @callback list_pizzas() :: list(Pizza.t())
    @callback get_pizza(id: String.t()) :: Pizza.t()
  end
end
