defmodule Pizza.Ports do
  alias Pizza.Core.Pizza
  alias Pizza.Event.CloudEvent

  defmodule Cli do
    @callback parse(command: list(String.t())) ::
                {:ok, Pizza.t() | list(Pizza.t())} | {:error, String.t()}
  end

  defmodule EventStore do
    @type config :: term()

    @callback migrate(term()) :: :ok | {:error, :migrations_error}
    @callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
    @callback get_event(term(), String.t(), pos_integer()) ::
                {:ok, CloudEvent.t()} | {:error, :not_found | :read_error}
  end

  defmodule PizzaProjection do
    @callback list_pizzas() :: list(Pizza.t())
    @callback get_pizza(id: String.t()) :: Pizza.t()
  end
end
