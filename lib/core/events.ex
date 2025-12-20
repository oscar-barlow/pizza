defmodule Pizza.Events.PizzaCreated do
  @moduledoc false

  @enforce_keys [:pizza_id, :name, :price, :occurred_at, :version]
  defstruct [:pizza_id, :name, :price, :occurred_at, :version]

  @type t :: %__MODULE__{
          pizza_id: String.t(),
          name: String.t(),
          price: number(),
          occurred_at: DateTime.t(),
          version: pos_integer()
        }
end

defmodule Pizza.Events.PriceChanged do
  @moduledoc false

  @enforce_keys [:pizza_id, :old_price, :new_price, :occurred_at, :version]
  defstruct [:pizza_id, :old_price, :new_price, :occurred_at, :version]

  @type t :: %__MODULE__{
          pizza_id: String.t(),
          old_price: number(),
          new_price: number(),
          occurred_at: DateTime.t(),
          version: pos_integer()
        }
end

defmodule Pizza.Events.PizzaRenamed do
  @moduledoc false

  @enforce_keys [:pizza_id, :old_name, :new_name, :occurred_at, :version]
  defstruct [:pizza_id, :old_name, :new_name, :occurred_at, :version]

  @type t :: %__MODULE__{
          pizza_id: String.t(),
          old_name: String.t(),
          new_name: String.t(),
          occurred_at: DateTime.t(),
          version: pos_integer()
        }
end
