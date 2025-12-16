defmodule Pizza.Adapters.PizzaProjection do
  @behaviour Pizza.Ports.PizzaProjection

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  @pizza_projection "pizza_projection"
  @all_partition "all"

  alias Pizza.Event.CloudEvent
  alias Pizza.Core.Pizza

  def default() do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def save(%__MODULE__{client: client}, %CloudEvent{
        data: %Pizza{} = pizza,
        version: version,
        time: time
      }) do
    projection_item = assemble_projection(pizza, version, time)

    opts = [
      condition_expression: "attribute_not_exists(version) OR :incoming_version > version",
      expression_attribute_values: %{incoming_version: version}
    ]

    case client.put_item(@pizza_projection, projection_item, opts) |> ExAws.request() do
      {:ok, _} ->
        {:ok, pizza.id}

      {:error, reason} ->
        {:error, :write_error,
         "Attempted to overwrite pizza with id #{pizza.id} and version #{version}: #{format_reason(reason)}"}
    end
  end

  @impl true
  def save(_, _) do
    {:error, :write_error, "Not a pizza"}
  end

  @impl true
  def get(%__MODULE__{client: client}, id) when is_binary(id) do
    key = %{"id" => id}

    case client.get_item(@pizza_projection, key) |> ExAws.request() do
      {:ok, %{"Item" => %{} = item}} when map_size(item) == 0 ->
        {:error, :not_found}

      {:ok, %{"Item" => item}} ->
        item
        |> ExAws.Dynamo.Decoder.decode()
        |> read_projection()

      {:ok, %{}} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, :read_error, format_reason(reason)}
    end
  end

  @impl true
  def list_alphabetical(%__MODULE__{client: client}, sort) when sort in [:asc, :desc] do
    query_opts = [
      index_name: "pizza_by_name",
      key_condition_expression: "#partition = :partition",
      expression_attribute_names: %{"#partition" => "all"},
      expression_attribute_values: %{partition: @all_partition},
      scan_index_forward: sort == :asc
    ]

    client.query(@pizza_projection, query_opts)
    |> ExAws.request()
    |> decode_collection()
  end

  def list_alphabetical(_, _), do: {:error, :invalid_sort_order}

  @impl true
  def list_chronological(%__MODULE__{client: client}, sort) when sort in [:asc, :desc] do
    query_opts = [
      index_name: "pizza_by_updated_at",
      key_condition_expression: "#partition = :partition",
      expression_attribute_names: %{"#partition" => "all"},
      expression_attribute_values: %{partition: @all_partition},
      scan_index_forward: sort == :asc
    ]

    client.query(@pizza_projection, query_opts)
    |> ExAws.request()
    |> decode_collection()
  end

  @impl true
  def list_by_price(%__MODULE__{client: client}, sort) when sort in [:asc, :desc] do
    query_opts = [
      index_name: "pizza_by_price",
      key_condition_expression: "#partition = :partition",
      expression_attribute_names: %{"#partition" => "all"},
      expression_attribute_values: %{partition: @all_partition},
      scan_index_forward: sort == :asc
    ]

    client.query(@pizza_projection, query_opts)
    |> ExAws.request()
    |> decode_collection()
  end

  @impl true
  def delete(%__MODULE__{client: client}, id) when is_binary(id) do
    key = %{"id" => id}

    case client.delete_item(@pizza_projection, key) |> ExAws.request() do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, :write_error, format_reason(reason)}
    end
  end

  defp assemble_projection(%Pizza{id: id, name: name, price: price}, version, %DateTime{} = time) do
    %{
      "id" => id,
      "version" => version,
      "all" => @all_partition,
      "name" => name,
      "price" => price,
      "updated_at" => DateTime.to_iso8601(time)
    }
  end

  defp read_projection(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza{id: id, name: name, price: price}}
  end

  defp read_projection(_), do: {:error, :invalid_projection}

  defp decode_collection({:ok, %{"Items" => items}}) do
    pizzas =
      items
      |> Enum.map(&ExAws.Dynamo.Decoder.decode/1)
      |> Enum.map(&read_projection/1)
      |> Enum.flat_map(fn
        {:ok, pizza} -> [pizza]
        _ -> []
      end)

    {:ok, pizzas}
  end

  defp decode_collection({:ok, _}), do: {:ok, []}
  defp decode_collection({:error, reason}), do: {:error, :read_error, format_reason(reason)}

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
