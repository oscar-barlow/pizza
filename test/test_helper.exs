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

defmodule Test.Eventually do
  @default_attempts 5
  @default_sleep_ms 20

  def eventually(fun, opts \\ []) when is_function(fun, 0) and is_list(opts) do
    attempts = Keyword.get(opts, :attempts, @default_attempts)
    sleep_ms = Keyword.get(opts, :sleep_ms, @default_sleep_ms)

    do_eventually(fun, attempts, sleep_ms)
  end

  defp do_eventually(fun, attempts, sleep_ms) when attempts > 0 do
    try do
      fun.()
    rescue
      error in [ExUnit.AssertionError] ->
        if attempts == 1 do
          reraise(error, __STACKTRACE__)
        else
          Process.sleep(sleep_ms)
          do_eventually(fun, attempts - 1, sleep_ms)
        end
    end
  end
end

ExUnit.start()
