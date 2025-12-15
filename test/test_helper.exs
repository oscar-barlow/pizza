defmodule Test.RepositoryHelper do

  def clear_tables do
    case ExAws.Dynamo.list_tables() |> ExAws.request() do
      {:ok, %{"TableNames" => tables}} -> :ok
      {:error, error} ->
        IO.puts("Error listing tables: ")
        IO.inspect(error)
    end
  end

  def clear_table(table) do
    IO.puts table
  end

end

ExUnit.start()
