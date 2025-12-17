defmodule Pizza.Application.Dispatcher do
  use GenServer

  alias Pizza.Application.EventStoreProcess
  alias Pizza.Application.PizzaProjectionProcess
  alias Pizza.Event.CloudEvent
  alias Pizza.Core.Pizza

  def start_link(opts \\ []) do
    start_opts = Keyword.take(opts, [:name])
    GenServer.start_link(__MODULE__, opts, start_opts)
  end

  def save_pizza(server, attrs), do: GenServer.call(server, {:save_pizza, attrs})

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
  def handle_call({:save_pizza, attrs}, _from, state) do
    with {:ok, pizza} <- build_pizza(attrs),
         {:ok, version} <- EventStoreProcess.next_version(state.event_store, pizza),
         {:ok, event} <- build_event(pizza, state.clock, version),
         {:ok, _} <- EventStoreProcess.store(state.event_store, event),
         {:ok, _} <- PizzaProjectionProcess.save(state.pizza_projection, event) do
      {:reply, {:ok, pizza}, state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:list_pizzas, list_type, order}, _from, state) do
    reply = list(state.pizza_projection, list_type, order)
    {:reply, reply, state}
  end

  defp build_pizza(%{name: name, price: price}) do
    Pizza.new(name, price)
  end

  defp build_pizza(_), do: {:error, :invalid_payload}

  defp build_event(%Pizza{} = pizza, clock, version) do
    event =
      CloudEvent.new_v1(
        :pizza_app,
        :pizza_saved,
        clock.(),
        pizza,
        version
      )

    {:ok, event}
  end

  defp list(pizza_projection, :alphabetical, order),
    do: PizzaProjectionProcess.list_alphabetical(pizza_projection, order)

  defp list(pizza_projection, :chronological, order),
    do: PizzaProjectionProcess.list_chronological(pizza_projection, order)

  defp list(pizza_projection, :price, order),
    do: PizzaProjectionProcess.list_by_price(pizza_projection, order)

  defp list(_projection, _list_type, _order), do: {:error, :unknown_list_type}
end
