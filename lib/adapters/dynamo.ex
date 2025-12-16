defmodule Pizza.Adapters.Dynamo do
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
    Enum.map(raw_definitions, fn %{attribute_name: name, attribute_type: type} ->
      {String.to_atom(name), attribute_type(type)}
    end)
  end

  def convert_key_schema(raw_schema) do
    Enum.map(raw_schema, fn %{attribute_name: name, key_type: type} ->
      {String.to_atom(name), key_type(type)}
    end)
  end

  def convert_billing_mode(raw_mode) do
    raw_mode
    |> String.downcase()
    |> String.to_atom()
  end

  def convert_global_secondary_indexes(raw_indexes) when is_list(raw_indexes) do
    Enum.map(raw_indexes, &convert_global_secondary_index/1)
  end

  def convert_global_secondary_indexes(_), do: []

  defp attribute_type(type) do
    Map.get(@attribute_type_map, type, normalize_to_atom(type))
  end

  defp key_type(type) do
    Map.get(@key_type_map, type, normalize_to_atom(type))
  end

  defp normalize_to_atom(value) do
    value
    |> String.downcase()
    |> String.to_atom()
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
