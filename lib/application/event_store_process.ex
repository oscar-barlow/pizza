defmodule Pizza.Application.EventStoreProcess do
  use GenServer

  alias Pizza.Event.CloudEvent
  alias Pizza.Adapters.EventStore

  def start_link(opts \\ []) do
    start_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def store(server, event), do: GenServer.call(server, {:store, event})

  def get_event(server, stream_id, version),
    do: GenServer.call(server, {:get_event, stream_id, version})

  def next_version(server, aggregate),
    do: GenServer.call(server, {:next_version, aggregate})

  @impl true
  def init(opts) do
    event_store_adapter = Keyword.get(opts, :adapter, EventStore)

    client = event_store_adapter.default()

    case event_store_adapter.migrate(client) do
      :ok -> {:ok, %{event_store_adapter: event_store_adapter, client: client}}
      {:error, reason} -> {:stop, {:migration_failed, reason}}
    end
  end

  @impl true
  def handle_call({:store, %CloudEvent{} = event}, _from, state) do
    %{event_store_adapter: event_store_adapter, client: client} = state

    {:reply, event_store_adapter.store(client, event), state}
  end

  @impl true
  def handle_call({:get_event, stream_id, version}, _from, state) do
    %{event_store_adapter: event_store_adapter, client: client} = state

    {:reply, event_store_adapter.get_event(client, stream_id, version), state}
  end

  @impl true
  def handle_call({:next_version, aggregate}, _from, state) do
    %{event_store_adapter: event_store_adapter, client: client} = state

    {:reply, event_store_adapter.next_version(client, aggregate), state}
  end

end
