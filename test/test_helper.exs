defmodule Test.RepositoryHelper do

  def clear_tables do
    ExAws.Dynamo.list_tables
      |> &(Enum.each(&1, clear_table/1))
  end

  def clear_table(table) do
    IO.puts table
  end

end

ExUnit.start()
