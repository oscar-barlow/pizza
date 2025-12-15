defmodule Pizza.Adapters.EventTest do
  use ExUnit.Case, async: true

  alias Pizza.Core.Pizza, as: CorePizza
  alias Pizza.Event.CloudEvent

  describe "when creating a cloud event" do
    test "builds a cloud event when the version is positive" do
      {:ok, pizza} = CorePizza.new("Margherita", 12.5)
      now = DateTime.utc_now()

      event = CloudEvent.new_v1(:cli, :create_pizza, now, pizza, 1)

      assert %CloudEvent{version: 1, time: ^now, data: ^pizza} = event
    end

    test "raises when the version is not a positive integer" do
      {:ok, pizza} = CorePizza.new("Margherita", 12.5)
      now = DateTime.utc_now()

      assert_raise ArgumentError, "cloud events require positive integer versions", fn ->
        CloudEvent.new_v1(:cli, :create_pizza, now, pizza, 0)
      end
    end
  end
end
