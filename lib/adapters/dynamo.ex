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
end
