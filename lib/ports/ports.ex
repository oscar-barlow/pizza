defmodule Pizza.Ports do
  alias Pizza.Event.CloudEvent
  alias Pizza.Core.Pizza

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
    @callback save(term(), CloudEvent.t()) ::
                {:ok, String.t()} | {:error, :write_error, String.t()}
    @callback list_alphabetical(term(), atom()) :: {:ok, list(Pizza.t())}
    @callback list_chronological(term(), atom()) :: {:ok, list(Pizza.t())}
    @callback list_by_price(term(), atom()) :: {:ok, list(Pizza.t())}
    @callback get(term(), String.t()) :: {:ok, Pizza.t()} | {:error, :not_found | :read_error}
    @callback delete(term(), String.t()) :: :ok | {:error, :write_error, String.t()}
  end
end
