defmodule Pizza.Adapters.Encoder do
  alias Pizza.Event.CloudEvent
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

  def encode(%Pizza{id: id, name: name, price: price}) do
    %{"id" => id, "name" => name, "price" => price}
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

  defp decode(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza{id: id, name: name, price: price}}
  end

  defp decode(_), do: {:error, :invalid_data}
end
