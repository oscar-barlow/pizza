defmodule Pizza.Adapters.Dynamo do
  require Logger

  @attribute_type_map %{
    "S" => :string,
    "N" => :number,
    "B" => :blob,
    "SS" => :string_set,
    "NS" => :number_set,
    "BS" => :blob_set,
    "BOOL" => :boolean,
    "NULL" => :null,
    "L" => :list,
    "M" => :map
  }

  @key_type_map %{
    "HASH" => :hash,
    "RANGE" => :range
  }

  def convert_attribute_definitions(raw_definitions) do
    raw_definitions
    |> Enum.reduce_while({:ok, []}, fn %{attribute_name: name, attribute_type: type}, {:ok, acc} ->
      case attribute_type(type) do
        {:ok, attr_type} -> {:cont, {:ok, [{safe_to_atom(name), attr_type} | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  def convert_key_schema(raw_schema) do
    raw_schema
    |> Enum.reduce_while({:ok, []}, fn %{attribute_name: name, key_type: type}, {:ok, acc} ->
      case key_type(type) do
        {:ok, k_type} -> {:cont, {:ok, [{safe_to_atom(name), k_type} | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      error -> error
    end
  end

  def convert_billing_mode(raw_mode) do
    {:ok, raw_mode |> String.downcase() |> safe_to_atom()}
  end

  def convert_global_secondary_indexes(raw_indexes) when is_list(raw_indexes) do
    {:ok, Enum.map(raw_indexes, &convert_global_secondary_index/1)}
  end

  def convert_global_secondary_indexes(_), do: {:ok, []}

  defp attribute_type(type) do
    case Map.fetch(@attribute_type_map, type) do
      {:ok, attr_type} -> {:ok, attr_type}
      :error -> {:error, {:unknown_attribute_type, type}}
    end
  end

  defp key_type(type) do
    case Map.fetch(@key_type_map, type) do
      {:ok, k_type} -> {:ok, k_type}
      :error -> {:error, {:unknown_key_type, type}}
    end
  end

  defp safe_to_atom(value) when is_binary(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError ->
      Logger.warning("Creating new atom from migration: #{value}")
      String.to_atom(value)
  end

  def convert_global_secondary_index(%{index_name: index_name, key_schema: raw_key_schema} = raw) do
    %{
      index_name: index_name,
      key_schema: convert_index_key_schema(raw_key_schema),
      projection: convert_projection(Map.get(raw, :projection)),
      provisioned_throughput:
        convert_provisioned_throughput(Map.get(raw, :provisioned_throughput))
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp convert_projection(nil), do: %{projection_type: "ALL"}

  defp convert_projection(%{projection_type: _} = projection) do
    projection
    |> Map.update!(:projection_type, &String.upcase(to_string(&1)))
  end

  defp convert_provisioned_throughput(nil), do: nil

  defp convert_provisioned_throughput(%{read_capacity_units: read, write_capacity_units: write}) do
    %{read_capacity_units: read, write_capacity_units: write}
  end

  defp convert_index_key_schema(raw_key_schema) when is_list(raw_key_schema) do
    Enum.map(raw_key_schema, fn %{attribute_name: name, key_type: type} ->
      %{attribute_name: name, key_type: String.upcase(to_string(type))}
    end)
  end

  defp convert_index_key_schema(_), do: []
end
