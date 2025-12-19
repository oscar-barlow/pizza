defmodule Pizza.Core.Pizza do
  @enforce_keys [:id, :name, :price, :version]
  defstruct id: nil, name: nil, price: nil, version: 0

  alias Pizza.Events.{PizzaCreated, PriceChanged, PizzaRenamed}

  @type t :: %__MODULE__{id: String.t(), name: String.t(), price: float(), version: integer()}
  @type domain_event :: PizzaCreated.t() | PriceChanged.t() | PizzaRenamed.t()

  def new(name, price)
      when is_binary(name) and byte_size(name) > 0 and is_number(price) and price > 0 do
    id = UUID.uuid4()
    pizza = %__MODULE__{id: id, name: name, price: price, version: 0}

    event = %PizzaCreated{
      pizza_id: id,
      name: name,
      price: price,
      occurred_at: DateTime.utc_now()
    }

    {:ok, pizza, [event]}
  end

  def new("", _price), do: {:error, :empty_name}
  def new(name, _price) when not is_binary(name), do: {:error, :invalid_name}
  def new(_name, price) when is_number(price) and price <= 0, do: {:error, :negative_price}
  def new(_name, _price), do: {:error, :invalid_price}

  def change_price(%__MODULE__{} = pizza, new_price)
      when is_number(new_price) and new_price > 0 do
    with :ok <- validate_price_change(pizza.price, new_price) do
      updated = %{pizza | price: new_price}

      event = %PriceChanged{
        pizza_id: pizza.id,
        old_price: pizza.price,
        new_price: new_price,
        occurred_at: DateTime.utc_now()
      }

      {:ok, updated, [event]}
    end
  end

  def change_price(%__MODULE__{}, price) when not is_number(price), do: {:error, :invalid_price}
  def change_price(%__MODULE__{}, price) when price <= 0, do: {:error, :negative_price}

  def rename(%__MODULE__{} = pizza, new_name)
      when is_binary(new_name) and byte_size(new_name) > 0 do
    updated = %{pizza | name: new_name}

    event = %PizzaRenamed{
      pizza_id: pizza.id,
      old_name: pizza.name,
      new_name: new_name,
      occurred_at: DateTime.utc_now()
    }

    {:ok, updated, [event]}
  end

  def rename(%__MODULE__{}, ""), do: {:error, :empty_name}
  def rename(%__MODULE__{}, name) when not is_binary(name), do: {:error, :invalid_name}

  def from_history(events) when is_list(events) do
    case reconstitute(events) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, pizza} -> {:ok, pizza}
      {:error, reason} -> {:error, reason}
    end
  end

  defp reconstitute(events) do
    Enum.reduce_while(events, {:ok, nil}, fn event, {:ok, pizza} ->
      case apply_event(event, pizza) do
        {:ok, updated} -> {:cont, {:ok, updated}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp apply_event(%PizzaCreated{pizza_id: id, name: name, price: price}, nil) do
    pizza = %__MODULE__{id: id, name: name, price: price, version: 1}
    {:ok, pizza}
  end

  defp apply_event(%PizzaCreated{}, %__MODULE__{}), do: {:error, :invalid_history}

  defp apply_event(%PriceChanged{new_price: new_price}, %__MODULE__{} = pizza) do
    {:ok, %{pizza | price: new_price, version: pizza.version + 1}}
  end

  defp apply_event(%PizzaRenamed{new_name: new_name}, %__MODULE__{} = pizza) do
    {:ok, %{pizza | name: new_name, version: pizza.version + 1}}
  end

  defp apply_event(_, _), do: {:error, :invalid_history}

  defp validate_price_change(old_price, new_price) do
    max_increase = old_price * 1.5

    cond do
      new_price > max_increase -> {:error, :price_increase_too_large}
      true -> :ok
    end
  end
end
