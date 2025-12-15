defmodule Pizza.Event do
  defmodule CloudEvent do
    @moduledoc """
    Refer to https://github.com/cloudevents/spec/blob/v1.0.2/cloudevents/spec.md
    """

  @derive Jason.Encoder
  @enforce_keys [:id, :stream_id, :version, :source, :specversion, :type, :time, :data]
    defstruct id: nil,
              stream_id: nil,
              version: nil,
              source: nil,
              specversion: nil,
              type: nil,
              time: nil,
              data: nil

    @type t :: %__MODULE__{
            id: String.t(),
            stream_id: String.t(),
            version: integer(),
            source: atom(),
            specversion: String.t(),
            type: atom(),
            time: String.t(),
            data: term()
          }

    def new_v1(source, type, %DateTime{} = time, data, version) when is_integer(version) and version > 0 do
      specversion = "1.0"
      stream_id = get_stream_id(data)

      %__MODULE__{
        id: UUID.uuid4(),
        stream_id: stream_id,
        version: version,
        source: source,
        specversion: specversion,
        type: type,
        time: time,
        data: data
      }
    end

    def new_v1(_source, _type, %DateTime{} = _time, _data, _version) do
      raise ArgumentError, "cloud events require positive integer versions"
    end

    def new_v1(_source, _type, _time, _data, _version) do
      raise ArgumentError, "cloud events require DateTime timestamps"
    end

    defp get_stream_id(%{id: id} = data) do
      aggregate_prefix =
        data.__struct__
        |> Module.split()
        |> List.last()
        |> Macro.underscore()

      "#{aggregate_prefix}-#{id}"
    end
  end
end
