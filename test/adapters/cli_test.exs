defmodule Pizza.Adapters.CliTest do
  use ExUnit.Case, async: true

  alias Pizza.Adapters.Cli
  alias Pizza.Core.Pizza

  describe "command parsing" do
    test "parses save command with price" do
      assert {:ok, {:save, %{name: "margherita", price: 7.5}}} =
               Cli.parse(["save", "margherita", "7.5"])
    end

    test "parses list command with defaults" do
      assert {:ok, {:list, :alphabetical, :asc}} = Cli.parse(["list", "alphabetical"])
    end

    test "parses list command with explicit order" do
      assert {:ok, {:list, :price, :desc}} = Cli.parse(["list", "price", "desc"])
    end

    test "rejects invalid price" do
      assert {:error, "Price must be a number"} = Cli.parse(["save", "margherita", "abc"])
    end

    test "passes through unknown scope" do
      assert {:ok, {:list, "bogus", :asc}} = Cli.parse(["list", "bogus"])
    end

    test "passes through unknown sort order" do
      assert {:ok, {:list, :alphabetical, "slow"}} = Cli.parse(["list", "alphabetical", "slow"])
    end

    test "rejects unknown commands" do
      assert {:error, "Unknown command"} = Cli.parse(["bogus"])
    end
  end

  describe "formatting" do
    test "formats save success" do
      pizza = %Pizza{id: "1", name: "margherita", price: 7.5}
      command = {:save, %{name: "margherita", price: 7.5}}

      assert "Saved pizza margherita (7.50)" == Cli.format({:ok, pizza}, command)
    end

    test "formats save error" do
      command = {:save, %{name: "margherita", price: 7.5}}

      assert "Invalid pizza attributes" == Cli.format({:error, :invalid_payload}, command)
    end

    test "formats empty list" do
      command = {:list, :alphabetical, :asc}

      assert "No pizzas found" == Cli.format({:ok, []}, command)
    end

    test "formats pizza list" do
      command = {:list, :alphabetical, :asc}

      pizzas = [
        %Pizza{id: "1", name: "margherita", price: 7.5},
        %Pizza{id: "2", name: "funghi", price: 9.0}
      ]

      assert "margherita (7.50)\nfunghi (9.00)" == Cli.format({:ok, pizzas}, command)
    end

    test "formats list error" do
      command = {:list, :alphabetical, :asc}

      assert "Failed to read data: :boom" == Cli.format({:error, {:read_error, :boom}}, command)
    end
  end
end
