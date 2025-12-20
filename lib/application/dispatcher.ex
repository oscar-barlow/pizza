defmodule Pizza.Application.Dispatcher do
  use GenServer

  alias Pizza.Application.EventStoreProcess
  alias Pizza.Application.PizzaProjectionProcess
  alias Pizza.Event.CloudEvent
  alias Pizza.Events
  alias Pizza.Core.Pizza

  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    start_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def create_pizza(name, price) when is_binary(name) and is_number(price) do
    create_pizza(__MODULE__, name, price)
  end

  def create_pizza(server, name, price), do: GenServer.call(server, {:create_pizza, name, price})

  def change_pizza_price(pizza_id, new_price) when is_binary(pizza_id) and is_number(new_price) do
    change_pizza_price(__MODULE__, pizza_id, new_price)
  end

  def change_pizza_price(server, pizza_id, new_price),
    do: GenServer.call(server, {:change_price, pizza_id, new_price})

  def rename_pizza(pizza_id, new_name) when is_binary(pizza_id) and is_binary(new_name) do
    rename_pizza(__MODULE__, pizza_id, new_name)
  end

  def rename_pizza(server, pizza_id, new_name),
    do: GenServer.call(server, {:rename, pizza_id, new_name})

  def delete_pizza(pizza_id) when is_binary(pizza_id) do
    delete_pizza(__MODULE__, pizza_id)
  end

  def delete_pizza(server, pizza_id), do: GenServer.call(server, {:delete, pizza_id})

  def list_pizzas(list_type, order) do
    list_pizzas(__MODULE__, list_type, order)
  end

  def list_pizzas(server, list_type, order),
    do: GenServer.call(server, {:list_pizzas, list_type, order})

  @impl true
  def init(opts) do
    event_store = Keyword.get(opts, :event_store, EventStoreProcess)
    pizza_projection = Keyword.get(opts, :pizza_projection, PizzaProjectionProcess)
    clock = Keyword.get(opts, :clock, &DateTime.utc_now/0)

    state = %{
      event_store: event_store,
      pizza_projection: pizza_projection,
      clock: clock
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_pizza, name, price}, _from, state) do
    with {:ok, domain_events} <- Pizza.new(name, price),
         {:ok, cloud_events} <- build_cloud_events(domain_events, state.clock),
         :ok <- store_events(state.event_store, cloud_events) do
      pizza_id = hd(domain_events).pizza_id
      publish_events(state.pizza_projection, cloud_events)
      {:reply, {:ok, pizza_id}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:change_price, pizza_id, new_price}, _from, state) do
    with {:ok, pizza} <- load_pizza(state.event_store, pizza_id),
         {:ok, domain_events} <- Pizza.change_price(pizza, new_price),
         {:ok, cloud_events} <- build_cloud_events(domain_events, state.clock),
         :ok <- store_events(state.event_store, cloud_events) do
      publish_events(state.pizza_projection, cloud_events)
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:rename, pizza_id, new_name}, _from, state) do
    with {:ok, pizza} <- load_pizza(state.event_store, pizza_id),
         {:ok, domain_events} <- Pizza.rename(pizza, new_name),
         {:ok, cloud_events} <- build_cloud_events(domain_events, state.clock),
         :ok <- store_events(state.event_store, cloud_events) do
      publish_events(state.pizza_projection, cloud_events)
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete, pizza_id}, _from, state) do
    with {:ok, pizza} <- load_pizza(state.event_store, pizza_id),
         {:ok, domain_events} <- Pizza.delete(pizza),
         {:ok, cloud_events} <- build_cloud_events(domain_events, state.clock),
         :ok <- store_events(state.event_store, cloud_events) do
      publish_events(state.pizza_projection, cloud_events)
      {:reply, :ok, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list_pizzas, list_type, order}, _from, state) do
    reply = list(state.pizza_projection, list_type, order)
    {:reply, reply, state}
  end



  defp build_cloud_events(domain_events, clock) do
    cloud_events =
      domain_events
      |> Enum.map(fn domain_event ->
        to_cloud_event(domain_event, clock.())
      end)

    {:ok, cloud_events}
  end

  defp to_cloud_event(%Events.PizzaCreated{version: version} = event, time) do
    CloudEvent.new_v1(:pizza_app, :pizza_created, time, event, version)
  end

  defp to_cloud_event(%Events.PriceChanged{version: version} = event, time) do
    CloudEvent.new_v1(:pizza_app, :price_changed, time, event, version)
  end

  defp to_cloud_event(%Events.PizzaRenamed{version: version} = event, time) do
    CloudEvent.new_v1(:pizza_app, :pizza_renamed, time, event, version)
  end

  defp to_cloud_event(%Events.PizzaDeleted{version: version} = event, time) do
    CloudEvent.new_v1(:pizza_app, :pizza_deleted, time, event, version)
  end

  defp store_events(event_store, cloud_events) do
    Enum.reduce_while(cloud_events, :ok, fn event, _acc ->
      case EventStoreProcess.store(event_store, event) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp publish_events(pizza_projection, cloud_events) do
    Enum.each(cloud_events, fn event ->
      GenServer.cast(pizza_projection, {event.type, event})
    end)
  end

  defp list(pizza_projection, :alphabetical, order),
    do: PizzaProjectionProcess.list_alphabetical(pizza_projection, order)

  defp list(pizza_projection, :chronological, order),
    do: PizzaProjectionProcess.list_chronological(pizza_projection, order)

  defp list(pizza_projection, :price, order),
    do: PizzaProjectionProcess.list_by_price(pizza_projection, order)

  defp list(_projection, _list_type, _order), do: {:error, :unknown_list_type}

  defp load_pizza(event_store, pizza_id) when is_binary(pizza_id) do
    stream_id = "pizza-#{pizza_id}"

    with {:ok, cloud_events} <- EventStoreProcess.get_stream(event_store, stream_id),
         {:ok, domain_events} <- unwrap_domain_events(cloud_events),
         {:ok, pizza} <- Pizza.from_history(domain_events) do
      {:ok, pizza}
    end
  end

  defp unwrap_domain_events(cloud_events) do
    domain_events = Enum.map(cloud_events, & &1.data)
    {:ok, domain_events}
  end
end
