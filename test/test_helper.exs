defmodule Test.RepositoryHelper do
  alias Pizza.Adapters.EventStore

  def ensure_tables! do
    store = EventStore.default()

    case EventStore.migrate(store) do
      :ok -> :ok
      {:error, :migrations_error} -> raise "failed to prepare Dynamo tables for tests"
    end
  end

  def clear_tables do
    case ExAws.Dynamo.list_tables() |> ExAws.request() do
      {:ok, %{"TableNames" => _tables}} -> :ok
      {:error, error} ->
        IO.puts("Error listing tables: ")
        IO.inspect(error)
    end
  end

  def clear_table(table) do
    IO.puts(table)
  end
end

Test.RepositoryHelper.ensure_tables!()

ExUnit.start()
