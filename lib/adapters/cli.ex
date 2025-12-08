defmodule Pizza.Adapters.Cli do
  @behaviour Pizza.Ports.Cli

  alias Pizza.Adapters.EventRepository
  alias Pizza.Core.Pizza

  @impl true
  def parse(command) do
    command
    |> run
  end

  defp run(["list"]) do
  end

  defp run(["save" | pizza]) do
    event_repository = EventRepository.default()

    with price <- String.to_float(tl(pizza)),
         {:ok, p} <- Pizza.new(pizza -- [price], price),
         {:ok, stored} <- EventRepository.store(event_repository, p) do
      {:ok, stored}
    end
  end
end
