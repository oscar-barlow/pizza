defmodule Pizza.Adapters.DynamoTest do
  use ExUnit.Case, async: true

  alias Pizza.Adapters.Dynamo

  describe "attribute definition conversion" do
    test "translates attribute definitions into Dynamo tuples" do
      raw = [
        %{attribute_name: "stream_id", attribute_type: "S"},
        %{attribute_name: "version", attribute_type: "N"}
      ]

      assert Dynamo.convert_attribute_definitions(raw) == [
               {:stream_id, :string},
               {:version, :number}
             ]
    end
  end

  describe "key schema conversion" do
    test "translates key schema entries into Dynamo tuples" do
      raw = [
        %{attribute_name: "stream_id", key_type: "HASH"},
        %{attribute_name: "version", key_type: "RANGE"}
      ]

      assert Dynamo.convert_key_schema(raw) == [
               {:stream_id, :hash},
               {:version, :range}
             ]
    end
  end

  describe "billing mode conversion" do
    test "normalises billing mode into an atom" do
      assert Dynamo.convert_billing_mode("PAY_PER_REQUEST") == :pay_per_request
      assert Dynamo.convert_billing_mode("PROVISIONED") == :provisioned
    end
  end

  describe "global secondary index conversion" do
    test "converts index definitions preserving key schema ordering" do
      raw = [
        %{
          index_name: "pizza_by_name",
          key_schema: [
            %{attribute_name: "all", key_type: "HASH"},
            %{attribute_name: "name", key_type: "range"}
          ]
        }
      ]

      assert Dynamo.convert_global_secondary_indexes(raw) == [
               %{
                 index_name: "pizza_by_name",
                 key_schema: [
                   %{attribute_name: "all", key_type: "HASH"},
                   %{attribute_name: "name", key_type: "RANGE"}
                 ],
                 projection: %{projection_type: "ALL"}
               }
             ]
    end

    test "retains provisioned throughput values when provided" do
      raw = [
        %{
          index_name: "pizza_by_price",
          key_schema: [
            %{attribute_name: "all", key_type: "HASH"},
            %{attribute_name: "price", key_type: "RANGE"}
          ],
          projection: %{projection_type: "KEYS_ONLY"},
          provisioned_throughput: %{read_capacity_units: 1, write_capacity_units: 2}
        }
      ]

      assert Dynamo.convert_global_secondary_indexes(raw) == [
               %{
                 index_name: "pizza_by_price",
                 key_schema: [
                   %{attribute_name: "all", key_type: "HASH"},
                   %{attribute_name: "price", key_type: "RANGE"}
                 ],
                 projection: %{projection_type: "KEYS_ONLY"},
                 provisioned_throughput: %{read_capacity_units: 1, write_capacity_units: 2}
               }
             ]
    end
  end
end
