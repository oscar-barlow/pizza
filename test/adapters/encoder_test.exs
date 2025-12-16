defmodule Pizza.Adapters.EncoderTest do
  use ExUnit.Case, async: true

  alias Pizza.Adapters.Encoder
  alias Pizza.Event.CloudEvent

  setup do
    pizza = %Pizza.Core.Pizza{id: "123", name: "margherita", price: 7.5}
    {:ok, pizza: pizza}
  end

  describe "encoding cloud events" do
    test "produces a Dynamo-friendly map", %{pizza: pizza} do
      time = DateTime.utc_now()

      event = CloudEvent.new_v1(:cli, :create_pizza, time, pizza, 1)

      encoded = Encoder.encode_cloud_event(event)

      assert encoded["stream_id"] == "pizza-123"
      assert encoded["version"] == 1
      assert encoded["id"] == event.id
      assert encoded["source"] == "cli"
      assert encoded["specversion"] == "1.0"
      assert encoded["type"] == "create_pizza"
      assert encoded["time"] == DateTime.to_iso8601(time)

      assert encoded["data"] == %{"id" => "123", "name" => "margherita", "price" => 7.5}
    end
  end

  describe "decoding cloud events" do
    test "reconstructs the original CloudEvent", %{pizza: pizza} do
      time = DateTime.utc_now() |> DateTime.truncate(:second)
      pizza = %Pizza.Core.Pizza{id: "123", name: "margherita", price: 7.5}
      event = CloudEvent.new_v1(:cli, :create_pizza, time, pizza, 1)

      payload = Encoder.encode_cloud_event(event)

      assert {:ok, decoded} = Encoder.decode_cloud_event(payload)

      assert decoded == event
    end

    test "returns an error when the payload is invalid" do
      assert {:error, :read_error} = Encoder.decode_cloud_event(%{"bad" => "data"})
    end
  end
end
