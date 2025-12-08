defmodule Pizza.Adapters.EventRepository do
  @behaviour Pizza.Ports.EventRepository

  alias Pizza.Event.PizzaEvent

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  def default do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def migrate(%__MODULE__{client: client} = _repo) do
    migration_name = "V1__create_events_table.json"
    migration_path = Path.join(:code.priv_dir(:pizza), "migrations/#{migration_name}")

    with {:ok, content} <- File.read(migration_path),
         {:ok, table_def} <- Jason.decode(content, keys: :atoms),
         %{
           table_name: table_name,
           attribute_definitions: raw_attr_defs,
           key_schema: raw_key_schema,
           billing_mode: raw_billing_mode
         } <- table_def do
      attr_defs = convert_attribute_definitions(raw_attr_defs)
      key_schema = convert_key_schema(raw_key_schema)
      billing_mode = convert_billing_mode(raw_billing_mode)

      opts = [billing_mode: billing_mode]
      client.create_table(table_name, key_schema, attr_defs, opts) |> ExAws.request

    else
      {:error, _} -> {:error, :migrations_error}
    end
  end

  @impl true
  def store(%__MODULE__{} = _repo, %PizzaEvent{} = pizza_event) do
    {:ok, pizza_event.id}
    # to do - save pizza event
  end

  defp convert_attribute_definitions(raw_defs) do
    Enum.map(raw_defs, fn %{attribute_name: name, attribute_type: type} ->
      {String.to_atom(name), aws_type_to_dynamo_type(type)}
    end)
  end

  defp convert_key_schema(raw_schema) do
    Enum.map(raw_schema, fn %{attribute_name: name, key_type: type} ->
      {String.to_atom(name), aws_key_type_to_atom(type)}
    end)
  end

  defp convert_billing_mode(raw_mode) do
    raw_mode
    |> String.downcase()
    |> String.to_atom()
  end

  defp aws_type_to_dynamo_type("S"), do: :string
  defp aws_type_to_dynamo_type("N"), do: :number
  defp aws_type_to_dynamo_type("B"), do: :blob
  defp aws_type_to_dynamo_type("SS"), do: :string_set
  defp aws_type_to_dynamo_type("NS"), do: :number_set
  defp aws_type_to_dynamo_type("BS"), do: :blob_set
  defp aws_type_to_dynamo_type("BOOL"), do: :boolean
  defp aws_type_to_dynamo_type("NULL"), do: :null
  defp aws_type_to_dynamo_type("L"), do: :list
  defp aws_type_to_dynamo_type("M"), do: :map

  defp aws_key_type_to_atom("HASH"), do: :hash
  defp aws_key_type_to_atom("RANGE"), do: :range
end
