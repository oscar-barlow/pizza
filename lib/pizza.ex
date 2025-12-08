defmodule Pizza.Main do
  alias Pizza.Adapters.Cli
  alias Pizza.Adapters.EventRepository

  def main(args \\ []) do
    event_repository = EventRepository.default()
    EventRepository.migrate(event_repository)

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
