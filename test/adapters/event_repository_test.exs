defmodule Pizza.Adapters.EventRepositoryTest do
  use ExUnit.Case

  alias Pizza.Adapters.EventRepository

  setup do
    event_repository = EventRepository.default()
    EventRepository.migrate(event_repository)
    Test.RepositoryHelper.clear_tables()
    {:ok, event_repository: event_repository}
  end

  test "do something" do
    assert false
  end
end
