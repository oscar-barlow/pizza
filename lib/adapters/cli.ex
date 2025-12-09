defmodule Pizza.Adapters.Cli do
  @behaviour Pizza.Ports.Cli

  @impl true
  def parse(command) do
    command
    |> run
  end

  defp run(["list"]) do
    {:error, "Not implemented"}
  end

  defp run(["save" | _pizza]) do
    {:error, "Not implemented"}
  end

  defp run(_) do
    {:error, "Unknown command"}
  end
end
