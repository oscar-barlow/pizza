defmodule Pizza.Adapters.PizzaProjection do
  @moduledoc false

  @behaviour Pizza.Ports.PizzaProjection

  alias Pizza.Event.CloudEvent
  alias Pizza.Events.{PizzaCreated, PriceChanged, PizzaRenamed}

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  @pizza_projection "pizza_projection"
  @all_partition "all"

  def default() do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def save(%__MODULE__{client: client}, %CloudEvent{
        data: %PizzaCreated{} = event,
        version: version,
        time: time
      }) do
    pizza = %Pizza.Core.Pizza{id: event.pizza_id, name: event.name, price: event.price, version: version}
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
  def save(%__MODULE__{client: client} = projection, %CloudEvent{
        data: %PriceChanged{} = event,
        version: version,
        time: time
      }) do
    case get(projection, event.pizza_id) do
      {:ok, existing_pizza} ->
        updated = %{existing_pizza | price: event.new_price, version: version}
        projection_item = assemble_projection(updated, version, time)

        opts = [
          condition_expression: ":incoming_version > version",
          expression_attribute_values: %{incoming_version: version}
        ]

        case client.put_item(@pizza_projection, projection_item, opts) |> ExAws.request() do
          {:ok, _} -> {:ok, event.pizza_id}
          {:error, reason} -> {:error, :write_error, format_reason(reason)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save(%__MODULE__{client: client} = projection, %CloudEvent{
        data: %PizzaRenamed{} = event,
        version: version,
        time: time
      }) do
    case get(projection, event.pizza_id) do
      {:ok, existing_pizza} ->
        updated = %{existing_pizza | name: event.new_name, version: version}
        projection_item = assemble_projection(updated, version, time)

        opts = [
          condition_expression: ":incoming_version > version",
          expression_attribute_values: %{incoming_version: version}
        ]

        case client.put_item(@pizza_projection, projection_item, opts) |> ExAws.request() do
          {:ok, _} -> {:ok, event.pizza_id}
          {:error, reason} -> {:error, :write_error, format_reason(reason)}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def save(_, _) do
    {:error, :write_error, "Unknown event type"}
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

  defp assemble_projection(%Pizza.Core.Pizza{id: id, name: name, price: price}, version, %DateTime{} = time) do
    %{
      "id" => id,
      "version" => version,
      "all" => @all_partition,
      "name" => name,
      "price" => price,
      "updated_at" => DateTime.to_iso8601(time)
    }
  end

  defp read_projection(%{"id" => id, "name" => name, "price" => price, "version" => version})
       when is_integer(version) do
    {:ok, %Pizza.Core.Pizza{id: id, name: name, price: price, version: version}}
  end

  defp read_projection(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza.Core.Pizza{id: id, name: name, price: price, version: 0}}
  end

  defp read_projection(_), do: {:error, :invalid_projection}

  defp decode_collection({:ok, %{"Items" => items}}) do
    pizzas =
      for item <- items,
          decoded = ExAws.Dynamo.Decoder.decode(item),
          {:ok, pizza} <- [read_projection(decoded)],
          do: pizza

    {:ok, pizzas}
  end

  defp decode_collection({:ok, _}), do: {:ok, []}
  defp decode_collection({:error, reason}), do: {:error, :read_error, format_reason(reason)}

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
