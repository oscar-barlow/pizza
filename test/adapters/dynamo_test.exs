defmodule Pizza.Adapters.DynamoTest do
  use ExUnit.Case, async: true

  alias Pizza.Adapters.Dynamo

  describe "attribute definition conversion" do
    test "translates attribute definitions into Dynamo tuples" do
      raw = [
        %{attribute_name: "stream_id", attribute_type: "S"},
        %{attribute_name: "version", attribute_type: "N"}
      ]

      assert {:ok, result} = Dynamo.convert_attribute_definitions(raw)
      assert result == [{:stream_id, :string}, {:version, :number}]
    end
  end

  describe "key schema conversion" do
    test "translates key schema entries into Dynamo tuples" do
      raw = [
        %{attribute_name: "stream_id", key_type: "HASH"},
        %{attribute_name: "version", key_type: "RANGE"}
      ]

      assert {:ok, result} = Dynamo.convert_key_schema(raw)
      assert result == [{:stream_id, :hash}, {:version, :range}]
    end
  end

  describe "billing mode conversion" do
    test "normalises billing mode into an atom" do
      assert {:ok, :pay_per_request} == Dynamo.convert_billing_mode("PAY_PER_REQUEST")
      assert {:ok, :provisioned} == Dynamo.convert_billing_mode("PROVISIONED")
    end
  end

  describe "error cases" do
    test "returns error for unknown attribute type" do
      raw = [%{attribute_name: "field", attribute_type: "UNKNOWN"}]

      assert {:error, {:unknown_attribute_type, "UNKNOWN"}} ==
        Dynamo.convert_attribute_definitions(raw)
    end

    test "returns error for unknown key type" do
      raw = [%{attribute_name: "field", key_type: "UNKNOWN"}]

      assert {:error, {:unknown_key_type, "UNKNOWN"}} ==
        Dynamo.convert_key_schema(raw)
    end
  end

  describe "edge cases" do
    test "handles empty attribute definitions list" do
      assert {:ok, []} == Dynamo.convert_attribute_definitions([])
    end

    test "handles empty key schema list" do
      assert {:ok, []} == Dynamo.convert_key_schema([])
    end

    test "handles non-list input for global secondary indexes" do
      assert {:ok, []} == Dynamo.convert_global_secondary_indexes(nil)
      assert {:ok, []} == Dynamo.convert_global_secondary_indexes("not a list")
      assert {:ok, []} == Dynamo.convert_global_secondary_indexes(%{})
    end

    test "converts GSI without explicit projection (defaults to ALL)" do
      raw = [
        %{
          index_name: "test_index",
          key_schema: [
            %{attribute_name: "pk", key_type: "HASH"}
          ]
        }
      ]

      assert {:ok, result} = Dynamo.convert_global_secondary_indexes(raw)
      assert [%{projection: %{projection_type: "ALL"}}] = result
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

      assert {:ok, result} = Dynamo.convert_global_secondary_indexes(raw)
      assert result == [
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

      assert {:ok, result} = Dynamo.convert_global_secondary_indexes(raw)
      assert result == [
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
