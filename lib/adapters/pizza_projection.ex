defmodule Pizza.Adapters.PizzaProjection do
  @behaviour Pizza.Ports.PizzaProjection

  defstruct [:client]

  @type t :: %__MODULE__{client: module()}

  @pizza_projection "pizza_projection"
  @all_partition "all"

  alias Pizza.Event.CloudEvent
  alias Pizza.Adapters.Encoder
  alias Pizza.Core.Pizza

  def default() do
    %__MODULE__{client: ExAws.Dynamo}
  end

  @impl true
  def save(%__MODULE__{client: client}, %CloudEvent{data: %Pizza{} = pizza, version: version, time: time}) do
    projection_item = assemble_projection(pizza, version, time)

    case client.put_item(@pizza_projection, projection_item) |> ExAws.request() do
      {:ok, _} -> {:ok, pizza.id}
      {:error, reason} -> {:error, :write_error, format_reason(reason)}
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
  def list_pizzas(%__MODULE__{client: client}) do
    client.scan(@pizza_projection)
    |> ExAws.request()
    |> case do
      {:ok, %{"Items" => items}} ->
        items
        |> Enum.map(&ExAws.Dynamo.Decoder.decode/1)
        |> Enum.map(&read_projection/1)
        |> Enum.flat_map(fn
          {:ok, pizza} -> [pizza]
          _ -> []
        end)

      {:ok, _} ->
        []

      {:error, _} ->
        []
    end
  end

  defp assemble_projection(%Pizza{id: id, name: name, price: price} = pizza, version, %DateTime{} = time) do
    %{
      "id" => id,
      "version" => version,
      "all" => @all_partition,
      "name" => name,
      "price" => price,
      "updated_at" => DateTime.to_iso8601(time),
      "payload" => Encoder.encode(pizza)
    }
  end

  defp read_projection(%{"payload" => payload}) do
    with {:ok, pizza} <- Encoder.decode_pizza(payload) do
      {:ok, pizza}
    end
  end

  defp read_projection(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza{id: id, name: name, price: price}}
  end

  defp read_projection(_), do: {:error, :invalid_projection}

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end
