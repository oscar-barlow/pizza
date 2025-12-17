defmodule Pizza.Application.PizzaProjectionProcess do
  use GenServer

  alias Pizza.Adapters.PizzaProjection
  alias Pizza.Event.CloudEvent

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    start_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def save(server, event), do: GenServer.call(server, {:save, event})

  def list_alphabetical(server, sort),
    do: GenServer.call(server, {:list_alphabetical, sort})

  def list_chronological(server, sort),
    do: GenServer.call(server, {:list_chronological, sort})

  def list_by_price(server, sort),
    do: GenServer.call(server, {:list_by_price, sort})

  def get(server, id), do: GenServer.call(server, {:get, id})

  def delete(server, id), do: GenServer.call(server, {:delete, id})

  @impl true
  def init(opts) do
    pizza_projection_adapter = Keyword.get(opts, :adapter, PizzaProjection)
    client = pizza_projection_adapter.default()

    {:ok, %{pizza_projection_adapter: pizza_projection_adapter, client: client}}
  end

  @impl true
  def handle_call({:save, %CloudEvent{} = event}, _from, state) do
    %{pizza_projection_adapter: pizza_projection_adapter, client: client} = state

    {:reply, pizza_projection_adapter.save(client, event), state}
  end

  @impl true
  def handle_call({:list_alphabetical, sort}, _from, state) do
    %{pizza_projection_adapter: pizza_projection_adapter, client: client} = state

    {:reply, pizza_projection_adapter.list_alphabetical(client, sort), state}
  end

  @impl true
  def handle_call({:list_chronological, sort}, _from, state) do
    %{pizza_projection_adapter: pizza_projection_adapter, client: client} = state

    {:reply, pizza_projection_adapter.list_chronological(client, sort), state}
  end

  @impl true
  def handle_call({:list_by_price, sort}, _from, state) do
    %{pizza_projection_adapter: pizza_projection_adapter, client: client} = state

    {:reply, pizza_projection_adapter.list_by_price(client, sort), state}
  end

  @impl true
  def handle_call({:get, id}, _from, state) do
    %{pizza_projection_adapter: pizza_projection_adapter, client: client} = state

    {:reply, pizza_projection_adapter.get(client, id), state}
  end

  @impl true
  def handle_call({:delete, id}, _from, state) do
    %{pizza_projection_adapter: pizza_projection_adapter, client: client} = state

    {:reply, pizza_projection_adapter.delete(client, id), state}
  end
end
