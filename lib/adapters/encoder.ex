defmodule Pizza.Adapters.JsonEncoders do
  alias Pizza.Core.Pizza
  require Protocol

  Protocol.derive(Jason.Encoder, Pizza, only: [:id, :name, :price])
end

defmodule Pizza.Adapters.Encoder do
  alias Pizza.Event.CloudEvent

  def encode_cloud_event(%CloudEvent{} = event) do
    %{
      "StreamId" => event.stream_id,
      "Version" => event.version,
      "Id" => event.id,
      "Source" => Atom.to_string(event.source),
      "SpecVersion" => event.specversion,
      "Type" => Atom.to_string(event.type),
      "Time" => encode_time(event.time),
      "Data" => encode_data(event.data)
    }
  end

  def decode_cloud_event(%{
        "StreamId" => stream_id,
        "Version" => version,
        "Id" => id,
        "Source" => source,
        "SpecVersion" => spec_version,
        "Type" => type,
        "Time" => time,
        "Data" => data
      }) do
    with {:ok, decoded_time} <- decode_time(time),
         {:ok, decoded_data} <- decode_data(data) do
      {:ok,
       %CloudEvent{
         id: id,
         stream_id: stream_id,
         version: normalize_version(version),
         source: decode_atom(source),
         specversion: spec_version,
         type: decode_atom(type),
         time: decoded_time,
         data: decoded_data
       }}
    else
      _ -> {:error, :read_error}
    end
  end

  def decode_cloud_event(_), do: {:error, :read_error}

  defp encode_time(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  defp encode_time(_), do: raise(ArgumentError, "Cloud events must carry DateTime structs")

  defp decode_time(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      _ -> {:error, :invalid_time}
    end
  end

  defp decode_time(_), do: {:error, :invalid_time}

  defp encode_data(%Pizza.Core.Pizza{id: id, name: name, price: price}) do
    %{"id" => id, "name" => name, "price" => price}
  end

  defp encode_data(value), do: value

  defp decode_data(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza.Core.Pizza{id: id, name: name, price: price}}
  end

  defp decode_data(value), do: {:ok, value}

  defp decode_atom(value) when is_atom(value), do: value

  defp decode_atom(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> String.to_atom(value)
    end
  end

  defp decode_atom(value), do: value

  defp normalize_version(value) when is_integer(value), do: value

  defp normalize_version(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> value
    end
  end

  defp normalize_version(value), do: value
end
