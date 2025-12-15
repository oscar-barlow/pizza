defmodule Pizza.Adapters.CliTest do
  use ExUnit.Case, async: true

  alias Pizza.Adapters.Cli

  describe "command parsing" do
    test "returns not implemented for list command" do
      assert {:error, "Not implemented"} = Cli.parse(["list"])
    end

    test "returns not implemented for save command" do
      assert {:error, "Not implemented"} = Cli.parse(["save", "margherita", "7.5"])
    end

    test "returns unknown command for unsupported input" do
      assert {:error, "Unknown command"} = Cli.parse(["bogus"])
    end
  end
end
