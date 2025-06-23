defmodule HagEx.ConfigTest do
  use ExUnit.Case, async: true
  require Logger

  alias HagEx.Config

  @test_config %{
    "hass_options" => %{
      "ws_url" => "ws://localhost:8123/api/websocket",
      "rest_url" => "http://localhost:8123",
      "token" => "test_token",
      "max_retries" => 3,
      "retry_delay_ms" => 500,
      "state_check_interval" => 300_000
    },
    "hvac_options" => %{
      "temp_sensor" => "sensor.test_temperature",
      "system_mode" => "auto",
      "hvac_entities" => [
        %{
          "entity_id" => "climate.test_ac",
          "enabled" => true,
          "defrost" => false
        }
      ],
      "heating" => %{
        "temperature" => 21.0,
        "preset_mode" => "comfort",
        "temperature_thresholds" => %{
          "indoor_min" => 19.0,
          "indoor_max" => 20.0,
          "outdoor_min" => -10.0,
          "outdoor_max" => 15.0
        },
        "defrost" => %{
          "temperature_threshold" => 0.0,
          "period_seconds" => 3600,
          "duration_seconds" => 300
        }
      },
      "cooling" => %{
        "temperature" => 24.0,
        "preset_mode" => "eco",
        "temperature_thresholds" => %{
          "indoor_min" => 23.0,
          "indoor_max" => 25.0,
          "outdoor_min" => 10.0,
          "outdoor_max" => 40.0
        }
      },
      "active_hours" => %{
        "start" => 8,
        "start_weekday" => 7,
        "end" => 22
      }
    }
  }

  describe "parse_config/1" do
    test "parses valid configuration correctly" do
      Logger.debug("Testing configuration parsing with full test config")
      {:ok, config} = Config.parse_config(@test_config)
      Logger.debug("Configuration parsed successfully")

      # Test HASS options
      Logger.debug("Validating HASS options: ws_url=#{config.hass_options.ws_url}")
      assert config.hass_options.ws_url == "ws://localhost:8123/api/websocket"
      assert config.hass_options.token == "test_token"
      assert config.hass_options.max_retries == 3

      # Test HVAC options
      Logger.debug("Validating HVAC options: sensor=#{config.hvac_options.temp_sensor}, mode=#{config.hvac_options.system_mode}")
      assert config.hvac_options.temp_sensor == "sensor.test_temperature"
      assert config.hvac_options.system_mode == :auto

      # Test HVAC entities
      Logger.debug("Validating HVAC entities: count=#{length(config.hvac_options.hvac_entities)}")
      assert length(config.hvac_options.hvac_entities) == 1
      entity = hd(config.hvac_options.hvac_entities)
      Logger.debug("Entity: #{entity.entity_id}, enabled=#{entity.enabled}, defrost=#{entity.defrost}")
      assert entity.entity_id == "climate.test_ac"
      assert entity.enabled == true
      assert entity.defrost == false

      # Test heating options
      heating = config.hvac_options.heating
      Logger.debug("Heating config: temp=#{heating.temperature}°C, preset=#{heating.preset_mode}")
      assert heating.temperature == 21.0
      assert heating.preset_mode == "comfort"
      assert heating.temperature_thresholds.indoor_min == 19.0
      assert heating.defrost.period_seconds == 3600

      # Test cooling options
      cooling = config.hvac_options.cooling
      Logger.debug("Cooling config: temp=#{cooling.temperature}°C, preset=#{cooling.preset_mode}")
      assert cooling.temperature == 24.0
      assert cooling.preset_mode == "eco"
      assert cooling.temperature_thresholds.indoor_max == 25.0

      # Test active hours
      active_hours = config.hvac_options.active_hours
      Logger.debug("Active hours: #{active_hours.start}-#{active_hours.end}, weekday_start=#{active_hours.start_weekday}")
      assert active_hours.start == 8
      assert active_hours.start_weekday == 7
      assert active_hours.end == 22
      
      Logger.debug("Full configuration validation completed successfully")
    end

    test "handles missing optional fields" do
      Logger.debug("Testing minimal configuration with default values")
      minimal_config = %{
        "hass_options" => %{
          "ws_url" => "ws://localhost:8123/api/websocket",
          "token" => "test_token"
        },
        "hvac_options" => %{
          "temp_sensor" => "sensor.test",
          "hvac_entities" => []
        }
      }

      {:ok, config} = Config.parse_config(minimal_config)
      Logger.debug("Minimal configuration parsed successfully")

      # Should use defaults for missing fields
      Logger.debug("Checking default values: retries=#{config.hass_options.max_retries}, delay=#{config.hass_options.retry_delay_ms}")
      assert config.hass_options.max_retries == 5
      assert config.hass_options.retry_delay_ms == 1000
      assert config.hvac_options.system_mode == :auto
      Logger.debug("Default values validation completed")
    end

    test "parses system_mode enum correctly" do
      Logger.debug("Testing system_mode enum parsing")
      test_cases = [
        {"heat_only", :heat_only},
        {"cool_only", :cool_only},
        {"auto", :auto},
        {"off", :off},
        # Should default to :auto
        {"invalid", :auto}
      ]

      for {input, expected} <- test_cases do
        Logger.debug("Testing system_mode: '#{input}' -> #{expected}")
        config = put_in(@test_config, ["hvac_options", "system_mode"], input)
        {:ok, parsed} = Config.parse_config(config)
        assert parsed.hvac_options.system_mode == expected
        Logger.debug("✓ System mode '#{input}' parsed correctly as #{expected}")
      end
      Logger.debug("All system_mode enum tests completed")
    end
  end
end
