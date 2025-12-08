defmodule Pizza.Event do
  defmodule CloudEvent do
    @enforce_keys [:id, :stream_id, :source, :specversion, :type, :time, :data]
    defstruct id: nil, stream_id: nil,source: nil, specversion: nil, type: nil, time: nil, data: nil

    @type t :: %__MODULE__{
            id: String.t(),
            stream_id: String.t(),
            source: atom(),
            specversion: integer(),
            type: atom(),
            time: String.t(),
            data: term()
          }

    def new_with_id_and_timestamp(source, specversion, type, data) do
      id = get_id()
      time = DateTime.utc_now()
      %__MODULE__{id: id, stream_id: stream_id, source: source, specversion: specversion, type: type, time: time, data: data}
    end

    defp get_id() do
      UUID.uuid4()
    end
  end
end
