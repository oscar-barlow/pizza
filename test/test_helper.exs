defmodule Test.RepositoryHelper do
  alias Pizza.Adapters.EventStore
  require Logger

  def drop_tables do
    case ExAws.Dynamo.list_tables() |> ExAws.request() do
      {:ok, %{"TableNames" => tables}} ->
        tables
        |> Enum.each(fn table ->
          ExAws.Dynamo.delete_table(table) |> ExAws.request()
        end)

      {:error, error} ->
        Logger.error("Error listing tables: #{inspect(error)}")
    end
  end

  def ensure_tables!, do: create_tables()

  def clear_tables do
    drop_tables()
    create_tables()
  end

  def clear_table(_table), do: :ok

  defp create_tables do
    store = EventStore.default()

    case EventStore.migrate(store) do
      :ok -> :ok
      {:error, :migrations_error} -> raise "failed to prepare Dynamo tables for tests"
    end
  end
end

Test.RepositoryHelper.ensure_tables!()

ExUnit.start()
