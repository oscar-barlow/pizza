defmodule Pizza.Main do
  alias Pizza.Adapters.Cli
  alias Pizza.Adapters.EventStore

  def main(args \\ []) do
    event_store = EventStore.default()
    EventStore.migrate(event_store)

    args
    |> parse
    |> IO.puts()
  end

  defp parse(args) do
    {_, command, _} = args |> OptionParser.parse()
    {:ok, out} = Cli.parse(command)
    out
  end
end
