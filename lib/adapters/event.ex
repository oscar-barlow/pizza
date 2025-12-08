defmodule Pizza.Event do
  defmodule CloudEvent do
    @enforce_keys [:stream_id, :id, :source, :specversion, :type, :time, :data]
    defstruct id: nil, source: nil, specversion: nil, type: nil, time: nil, data: nil

    @type t :: %__MODULE__{
            stream_id: String.t(),
            id: String.t(),
            source: atom(),
            specversion: integer(),
            type: atom(),
            time: String.t(),
            data: term()
          }

    def new_with_id_and_timestamp(source, specversion, type, data) do
      id = get_id()
      time = DateTime.utc_now()
      %PizzaEvent{id: id, source: source, specversion: specversion, type: type, time: time, data: data}
    end

    defp get_id() do
      UUID.uuid4()
    end
  end
end
