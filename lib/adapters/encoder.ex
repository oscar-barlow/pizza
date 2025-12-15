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
      "Time" => DateTime.to_iso8601(event.time),
      "Data" => encode(event.data)
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

  defp encode(%Pizza.Core.Pizza{id: id, name: name, price: price}) do
    %{"id" => id, "name" => name, "price" => price}
  end

  defp decode(%{"id" => id, "name" => name, "price" => price}) do
    {:ok, %Pizza.Core.Pizza{id: id, name: name, price: price}}
  end

  defp decode(_), do: {:error, :invalid_data}

end
