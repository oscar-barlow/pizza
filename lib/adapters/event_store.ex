defmodule Pizza.Adapters.EventStore do
  @behaviour Pizza.Ports.EventStore

  alias Pizza.Adapters.{Dynamo, Encoder}
  alias Pizza.Event.CloudEvent
  require Logger

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  @events_table "events"

  def default() do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def migrate(%__MODULE__{} = store) do
    :code.priv_dir(:pizza)
    |> Path.join("migrations/**.json")
    |> Path.wildcard()
    |> Enum.reduce_while(:ok, fn migration, acc ->
      Logger.info("Found migration: #{migration}")

      case perform_migration(store, migration) do
        :ok -> {:cont, acc}
        {:error, :migrations_error} = error -> {:halt, error}
      end
    end)
  end

  def perform_migration(%__MODULE__{client: client}, migration) do
    with {:ok, content} <- File.read(migration),
         _ <- Logger.debug("[EventStore] migration file '#{migration}' read successfully"),
         {:ok, table_def} <- Jason.decode(content, keys: :atoms),
         _ <- Logger.debug("[EventStore] migration '#{migration}' JSON decoded"),
         %{
           table_name: table_name,
           attribute_definitions: raw_attr_defs,
           key_schema: raw_key_schema,
           billing_mode: raw_billing_mode
         } <- table_def do
      Logger.info("[EventStore] applying migration '#{migration}' to table #{table_name}")
      attr_defs = Dynamo.convert_attribute_definitions(raw_attr_defs)
      key_schema = Dynamo.convert_key_schema(raw_key_schema)
      billing_mode = Dynamo.convert_billing_mode(raw_billing_mode)
      raw_gsis = Map.get(table_def, :global_secondary_indexes, [])
      global_secondary_indexes = Dynamo.convert_global_secondary_indexes(raw_gsis)

      opts =
        [billing_mode: billing_mode]
        |> maybe_put_global_indexes(global_secondary_indexes)

      case client.create_table(table_name, key_schema, attr_defs, opts) |> ExAws.request() do
        {:ok, _} ->
          Logger.info("[EventStore] table #{table_name} created, waiting for ACTIVE state")
          wait_for_table(client, table_name)

        {:error, {"ResourceInUseException", _}} ->
          Logger.info("[EventStore] table #{table_name} already exists, ensuring ACTIVE state")

          wait_for_table(client, table_name)

        {:error, reason} ->
          Logger.error("[EventStore] failed to create table #{table_name}: #{inspect(reason)}")

          {:error, :migrations_error}
      end
    else
      {:error, reason} ->
        Logger.error("[EventStore] migration #{migration} failed: #{inspect(reason)}")
        {:error, :migrations_error}
    end
  end

  @impl true
  def store(%__MODULE__{client: client}, %CloudEvent{} = event) do
    item = Encoder.encode_cloud_event(event)
    opts = [condition_expression: "attribute_not_exists(stream_id)"]

    case client.put_item(@events_table, item, opts) |> ExAws.request() do
      {:ok, _} -> {:ok, event.id}
      {:error, reason} -> {:error, {:write_error, reason}}
    end
  end

  @impl true
  def get_event(%__MODULE__{client: client}, stream_id, version)
      when is_binary(stream_id) and is_integer(version) and version > 0 do
    key = %{"stream_id" => stream_id, "version" => version}

    case client.get_item(@events_table, key) |> ExAws.request() do
      {:ok, %{"Item" => %{} = item}} when map_size(item) == 0 ->
        {:error, :not_found}

      {:ok, %{"Item" => item}} ->
        item
        |> ExAws.Dynamo.Decoder.decode()
        |> Encoder.decode_cloud_event()

      {:ok, %{}} ->
        {:error, :not_found}

      {:error, _} ->
        {:error, :read_error}
    end
  end

  @impl true
  def next_version(%__MODULE__{client: client}, aggregate)
      when is_map(aggregate) do
    stream_id = CloudEvent.stream_id_for(aggregate)

    query_opts = [
      key_condition_expression: "#stream_id = :stream_id",
      expression_attribute_names: %{"#stream_id" => "stream_id"},
      expression_attribute_values: %{stream_id: stream_id},
      projection_expression: "version",
      scan_index_forward: false,
      limit: 1
    ]

    case client.query(@events_table, query_opts) |> ExAws.request() do
      {:ok, %{"Items" => [item | _]}} ->
        decoded = ExAws.Dynamo.Decoder.decode(item)
        version = Map.get(decoded, "version") || Map.get(decoded, :version)
        normalize_version(version)

      {:ok, %{"Items" => []}} ->
        {:ok, 1}

      {:ok, %{}} ->
        {:ok, 1}

      {:error, reason} ->
        Logger.error("[EventStore] failed to determine next version for #{stream_id}: #{inspect(reason)}")
        {:error, {:read_error, reason}}
    end
  rescue
    e in ArgumentError ->
      Logger.error("[EventStore] #{Exception.message(e)}")
      {:error, :invalid_aggregate}
  end

  def next_version(%__MODULE__{}, _aggregate) do
    {:error, :invalid_aggregate}
  end

  defp wait_for_table(client, table_name), do: wait_for_table(client, table_name, 10, 100)

  defp wait_for_table(client, table_name, attempts, delay) do
    case client.describe_table(table_name) |> ExAws.request() do
      {:ok, %{"Table" => %{"TableStatus" => "ACTIVE"}}} ->
        Logger.info("[EventStore] Table with name '#{table_name}' active")
        :ok

      {:ok, _} ->
        Process.sleep(delay)
        Logger.info("[EventStore] Table #{table_name} not active yet")
        wait_for_table(client, table_name, attempts - 1, next_delay(delay))

      {:error, {"ResourceNotFoundException", _}} ->
        Logger.warning("[EventStore] Table with name '#{table_name}' not found")
        Process.sleep(delay)
        wait_for_table(client, table_name, attempts - 1, next_delay(delay))

      {:error, _} ->
        Logger.error("[EventStore] Error migrating table with name '#{table_name}'")
        {:error, :migrations_error}
    end
  end

  defp next_delay(delay), do: min(delay + 100, 1_000)

  defp maybe_put_global_indexes(opts, []), do: opts

  defp maybe_put_global_indexes(opts, indexes), do: Keyword.put(opts, :global_indexes, indexes)

  defp normalize_version(nil), do: {:error, :invalid_version}
  defp normalize_version(version) when is_integer(version), do: {:ok, version + 1}
  defp normalize_version(%{"N" => number}) do
    number
    |> String.to_integer()
    |> normalize_version()
  end
  defp normalize_version(version) when is_binary(version) do
    version
    |> String.to_integer()
    |> normalize_version()
  rescue
    ArgumentError -> {:error, :invalid_version}
  end
  defp normalize_version(_), do: {:error, :invalid_version}
end
