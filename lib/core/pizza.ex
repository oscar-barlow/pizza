defmodule Pizza.Core.Pizza do
  @enforce_keys [:id, :name, :price]
  defstruct id: nil, name: nil, price: nil

  @type t :: %__MODULE__{id: String.t(), name: String.t(), price: float()}

  def new(name, price)
      when is_binary(name) and byte_size(name) > 0 and is_number(price) and price > 0 do
    {:ok, %__MODULE__{id: UUID.uuid4(), name: name, price: price}}
  end

  def new("", _price), do: {:error, :empty_name}
  def new(name, _price) when not is_binary(name), do: {:error, :invalid_name}
  def new(_name, price) when is_number(price) and price <= 0, do: {:error, :negative_price}
  def new(_name, _price), do: {:error, :invalid_price}
end
