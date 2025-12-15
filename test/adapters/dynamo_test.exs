defmodule Pizza.Adapters.DynamoTest do
  use ExUnit.Case, async: true

  alias Pizza.Adapters.Dynamo

  describe "attribute definition conversion" do
    test "translates attribute definitions into Dynamo tuples" do
      raw = [
        %{attribute_name: "StreamId", attribute_type: "S"},
        %{attribute_name: "Version", attribute_type: "N"}
      ]

      assert Dynamo.convert_attribute_definitions(raw) == [
               {:StreamId, :string},
               {:Version, :number}
             ]
    end
  end

  describe "key schema conversion" do
    test "translates key schema entries into Dynamo tuples" do
      raw = [
        %{attribute_name: "StreamId", key_type: "HASH"},
        %{attribute_name: "Version", key_type: "RANGE"}
      ]

      assert Dynamo.convert_key_schema(raw) == [
               {:StreamId, :hash},
               {:Version, :range}
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
            %{attribute_name: "All", key_type: "HASH"},
            %{attribute_name: "Name", key_type: "range"}
          ]
        }
      ]

      assert Dynamo.convert_global_secondary_indexes(raw) == [
               %{
                 index_name: "pizza_by_name",
                 key_schema: [
                   %{attribute_name: "All", key_type: "HASH"},
                   %{attribute_name: "Name", key_type: "RANGE"}
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
            %{attribute_name: "All", key_type: "HASH"},
            %{attribute_name: "Price", key_type: "RANGE"}
          ],
          projection: %{projection_type: "KEYS_ONLY"},
          provisioned_throughput: %{read_capacity_units: 1, write_capacity_units: 2}
        }
      ]

      assert Dynamo.convert_global_secondary_indexes(raw) == [
               %{
                 index_name: "pizza_by_price",
                 key_schema: [
                   %{attribute_name: "All", key_type: "HASH"},
                   %{attribute_name: "Price", key_type: "RANGE"}
                 ],
                 projection: %{projection_type: "KEYS_ONLY"},
                 provisioned_throughput: %{read_capacity_units: 1, write_capacity_units: 2}
               }
             ]
    end
  end
end
