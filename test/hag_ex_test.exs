defmodule HagExTest do
  use ExUnit.Case
  doctest HagEx

  test "greets the world" do
    assert HagEx.hello() == :world
  end
end
