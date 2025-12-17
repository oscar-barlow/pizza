defmodule Pizza.Ports do
  alias Pizza.Event.CloudEvent
  alias Pizza.Core.Pizza

  defmodule Cli do
    @type save_command :: {:save, %{name: String.t(), price: float()}}
    @type list_scope :: :alphabetical | :chronological | :price
    @type sort_order :: :asc | :desc
    @type list_command :: {:list, list_scope(), sort_order()}
    @type command :: save_command() | list_command()
    @type result :: {:ok, term()} | {:error, term()}

    @callback parse(list(String.t())) :: {:ok, command()} | {:error, String.t()}
    @callback format(result(), command()) :: String.t()
  end

  defmodule EventStore do
    @type config :: term()

    @callback migrate(term()) :: :ok | {:error, :migrations_error}
    @callback store(term(), CloudEvent.t()) :: {:ok, String.t()} | {:error, :write_error}
    @callback get_event(term(), String.t(), pos_integer()) ::
                {:ok, CloudEvent.t()} | {:error, :not_found | :read_error}
    @callback next_version(term(), term()) :: {:ok, pos_integer()} | {:error, term()}
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
