defmodule HagExTest do
  use ExUnit.Case
  doctest HagEx

  test "application loads configuration" do
    # Test that the configuration loading works
    assert {:ok, _config} = HagEx.Config.load("config/hvac_config_test.yaml")
  end
end
