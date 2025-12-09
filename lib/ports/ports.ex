defmodule Pizza.Ports do
  alias Pizza.Core.Pizza
  alias Pizza.Event.CloudEvent

  defmodule Cli do
    @callback parse(command: list(String.t())) ::
                {:ok, Pizza.t() | list(Pizza.t())} | {:error, String.t()}
  end

  defmodule EventRepository do
    @type config :: term()

    @callback migrate(term()) :: :ok | {:error, :migrations_error}
    @callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
    @callback get_event(term(), String.t()) :: {:ok, CloudEvent.t()} | {:error, :read_error}
  end

  defmodule PizzaProjectionRepository do
    @callback list_pizzas() :: list(Pizza.t())
    @callback get_pizza(id: String.t()) :: Pizza.t()
  end
end
