defmodule Pizza.Adapters.Encoder do
  @moduledoc false

  alias Pizza.Event.CloudEvent
  alias Pizza.Events
  alias Pizza.Core.Pizza

  def encode_cloud_event(%CloudEvent{} = event) do
    %{
      "stream_id" => event.stream_id,
      "version" => event.version,
      "id" => event.id,
      "source" => Atom.to_string(event.source),
      "specversion" => event.specversion,
      "type" => Atom.to_string(event.type),
      "time" => DateTime.to_iso8601(event.time),
      "data" => encode(event.data)
    }
  end

  def decode_cloud_event(%{
        "stream_id" => stream_id,
        "version" => version,
        "id" => id,
        "source" => source,
        "specversion" => spec_version,
        "type" => type,
        "time" => time,
        "data" => data
      }) do
    with {:ok, decoded_time} <- decode_time(time),
         {:ok, decoded_data} <- decode(data),
         {:ok, normalised_version} <- normalise_version(version) do
      {:ok,
       %CloudEvent{
         id: id,
         stream_id: stream_id,
         version: normalised_version,
         source: String.to_existing_atom(source),
         specversion: spec_version,
         type: String.to_existing_atom(type),
         time: decoded_time,
         data: decoded_data
       }}
    else
      _ -> {:error, :read_error}
    end
  end

  def decode_cloud_event(_), do: {:error, :read_error}

  def encode(%Pizza{id: id, name: name, price: price, version: version}) do
    %{"id" => id, "name" => name, "price" => price, "version" => version}
  end

  def encode(%Events.PizzaCreated{} = event) do
    %{
      "pizza_id" => event.pizza_id,
      "name" => event.name,
      "price" => event.price,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "version" => event.version
    }
  end

  def encode(%Events.PriceChanged{} = event) do
    %{
      "pizza_id" => event.pizza_id,
      "old_price" => event.old_price,
      "new_price" => event.new_price,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "version" => event.version
    }
  end

  def encode(%Events.PizzaRenamed{} = event) do
    %{
      "pizza_id" => event.pizza_id,
      "old_name" => event.old_name,
      "new_name" => event.new_name,
      "occurred_at" => DateTime.to_iso8601(event.occurred_at),
      "version" => event.version
    }
  end

  def decode_pizza(payload), do: decode(payload)

  defp decode_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_time}
    end
  end

  defp normalise_version(version) when is_integer(version), do: {:ok, version}

  defp normalise_version(version) when is_binary(version) do
    case Integer.parse(version) do
      {parsed, ""} -> {:ok, parsed}
      _ -> {:error, :invalid_version}
    end
  end

  defp normalise_version(_), do: {:error, :invalid_version}

  defp decode(%{"id" => id, "name" => name, "price" => price, "version" => version}) do
    {:ok, %Pizza{id: id, name: name, price: price, version: version}}
  end

  defp decode(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza{id: id, name: name, price: price, version: 0}}
  end

  defp decode(%{"pizza_id" => pizza_id, "name" => name, "price" => price, "occurred_at" => occurred_at, "version" => version}) do
    with {:ok, time} <- decode_time(occurred_at) do
      {:ok, %Events.PizzaCreated{pizza_id: pizza_id, name: name, price: price, occurred_at: time, version: version}}
    end
  end

  defp decode(%{"pizza_id" => pizza_id, "old_price" => old_price, "new_price" => new_price, "occurred_at" => occurred_at, "version" => version}) do
    with {:ok, time} <- decode_time(occurred_at) do
      {:ok, %Events.PriceChanged{pizza_id: pizza_id, old_price: old_price, new_price: new_price, occurred_at: time, version: version}}
    end
  end

  defp decode(%{"pizza_id" => pizza_id, "old_name" => old_name, "new_name" => new_name, "occurred_at" => occurred_at, "version" => version}) do
    with {:ok, time} <- decode_time(occurred_at) do
      {:ok, %Events.PizzaRenamed{pizza_id: pizza_id, old_name: old_name, new_name: new_name, occurred_at: time, version: version}}
    end
  end

  defp decode(_), do: {:error, :invalid_data}
end
