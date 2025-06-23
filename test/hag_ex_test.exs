defmodule HagExTest do
  use ExUnit.Case
  doctest HagEx
  require Logger

  test "application loads configuration" do
    Logger.debug("Testing configuration loading from hvac_config_test.yaml")
    
    # Test that the configuration loading works
    assert {:ok, config} = HagEx.Config.load("config/hvac_config_test.yaml")
    
    Logger.debug("Configuration loaded successfully: system_mode=#{config.hvac_options.system_mode}")
    Logger.debug("HVAC entities count: #{length(config.hvac_options.hvac_entities)}")
    Logger.debug("Temperature sensor: #{config.hvac_options.temp_sensor}")
    
    assert config.hvac_options.system_mode == :auto
    assert length(config.hvac_options.hvac_entities) == 1
    
    Logger.debug("Configuration validation completed successfully")
  end
end
