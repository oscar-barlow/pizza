defmodule Pizza.Adapters.Cli do
  @behaviour Pizza.Ports.Cli

  alias Pizza.Core.Pizza

  @impl true
  def parse(["save", name, price_string]) do
    case Float.parse(price_string) do
      {price, ""} -> {:ok, {:save, %{name: name, price: price}}}
      _ -> {:error, "Price must be a number"}
    end
  end

  def parse(["list", scope]) do
    parse(["list", scope, "asc"])
  end

  def parse(["list", scope, order]) do
    {:ok, {:list, cast_atom(scope), cast_atom(order)}}
  end

  def parse(_), do: {:error, "Unknown command"}

  defp cast_atom(value) when is_binary(value) do
    lowercase = String.downcase(value)

    try do
      String.to_existing_atom(lowercase)
    rescue
      ArgumentError -> lowercase
    end
  end

  @impl true
  def format({:ok, %Pizza{} = pizza}, {:save, _}) do
    "Saved pizza #{pizza.name} (#{format_price(pizza.price)})"
  end

  def format({:error, reason}, {:save, _}) do
    format_error(reason)
  end

  def format({:ok, pizzas}, {:list, _scope, _order}) when pizzas == [] do
    "No pizzas found"
  end

  def format({:ok, pizzas}, {:list, _scope, _order}) when is_list(pizzas) do
    pizzas
    |> Enum.map(&format_pizza/1)
    |> Enum.join("\n")
  end

  def format({:error, reason}, {:list, _scope, _order}) do
    format_error(reason)
  end

  def format({:error, message}, {:error, _}) when is_binary(message), do: message
  def format({:error, reason}, _command), do: format_error(reason)
  def format({:ok, result}, _command), do: inspect(result)

  defp format_pizza(%Pizza{name: name, price: price}) do
    "#{name} (#{(price)})"
  end

  defp format_error(:invalid_payload), do: "Invalid pizza attributes"
  defp format_error(:negative_price), do: "Price must be greater than zero"
  defp format_error({:write_error, reason}), do: "Failed to write data: #{inspect(reason)}"
  defp format_error({:read_error, reason}), do: "Failed to read data: #{inspect(reason)}"
  defp format_error({:invalid_version}), do: "Invalid event version"
  defp format_error({:unknown_list_type}), do: "Unknown list scope"
  defp format_error(reason), do: "Error: #{inspect(reason)}"

  defp format_price(price) do
    :erlang.float_to_binary(price, decimals: 2)
  end
end
