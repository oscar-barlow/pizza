defmodule Pizza.Application do
  use Application

  alias Pizza.Adapters.Cli
  alias Pizza.Adapters.EventStore
  alias Pizza.Application.Dispatcher
  alias Pizza.Application.EventStoreProcess
  alias Pizza.Application.PizzaProjectionProcess

  def start(_type, _args) do
    with :ok <- migrate_event_store() do
      children = [
        {EventStoreProcess, [name: EventStoreProcess]},
        {PizzaProjectionProcess, [name: PizzaProjectionProcess]},
        {Dispatcher,
         [
           name: Dispatcher,
           event_store: EventStoreProcess,
           pizza_projection: PizzaProjectionProcess
         ]}
      ]

      Supervisor.start_link(children, strategy: :one_for_one, name: Pizza.Supervisor)
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  def main(args \\ []) do
    Application.ensure_all_started(:pizza)

    args
    |> parse()
    |> handle_command()
    |> IO.puts()
  end

  defp parse(args) do
    {_, command, _} = OptionParser.parse(args, strict: [])
    Cli.parse(command)
  end

  defp migrate_event_store do
    EventStore.default()
    |> EventStore.migrate()
  end

  defp handle_command({:ok, command}) do
    command
    |> dispatch()
    |> then(&Cli.format(&1, command))
  end

  defp handle_command({:error, message}), do: message

  defp dispatch({:save, attrs}), do: Dispatcher.save_pizza(attrs)
  defp dispatch({:list, scope, order}), do: Dispatcher.list_pizzas(scope, order)

end
