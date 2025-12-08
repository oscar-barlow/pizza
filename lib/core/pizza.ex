defmodule Pizza.Core.Pizza do
  @enforce_keys [:id, :name, :price]
  defstruct id: nil, name: nil, price: nil

  @type t :: %__MODULE__{id: String.t(), name: String.t(), price: float()}

  def new(name, price) do
    case price > 0 do
      true ->
        id = get_id()
        {:ok, %__MODULE__{id: id, name: name, price: price}}

      _ ->
        {:error, :negative_price}
    end
  end

  defp get_id() do
    UUID.uuid4()
  end
end
