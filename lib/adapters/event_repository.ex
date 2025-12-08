defmodule Pizza.Adapters.EventRepository do
  @behaviour Pizza.Ports.EventRepository

  alias Pizza.Core.Pizza

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  def default do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def migrate(%__MODULE__{client: client} = _repo) do
    migration_path = Path.join([:code.priv_dir(:pizza), "..", "migrations", "V1__create_events_table.json"])

    with {:ok, content} <- File.read(migration_path),
         {:ok, table_def} <- Jason.decode(content, keys: :atoms),
         table_name <- get_table_name(),
         %{
           attribute_definitions: attr_defs,
           key_schema: key_schema,
           billing_mode: billing_mode
         } <- table_def do
      opts = [billing_mode: billing_mode]
      case client.create_table(table_name, attr_defs, key_schema, opts) |> client.request() do
        {:ok, _} -> :ok
        {:error, {"ResourceInUseException", _}} -> :ok
        {:error, _} -> {:error, :migrations_error}
      end
    else
      {:error, _} -> {:error, :migrations_error}
    end
  end

  @impl true
  def store(%__MODULE__{} = _repo, %Pizza{} = pizza) do
    {:ok, pizza}
  end

  defp get_table_name do
    Application.get_env(:pizza, :events_table, "pizza_events")
  end
end
