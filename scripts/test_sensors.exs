
#!/usr/bin/env elixir

# Test Sensor Availability Script
# Tests if specific temperature sensors exist in Home Assistant

defmodule TestSensors do
  require Logger
  alias HagEx.HomeAssistant.Client

  def main() do
    case Client.connect() do
      :ok ->
        Logger.info("Connected successfully")

        # Try different sensor names
        sensors = [
          "sensor.1st_floor_hall_multisensor_temperature",
          "sensor.openweathermap_temperature",
          "sensor.temperature",
          "sensor.indoor_temperature",
          "sensor.outdoor_temperature"
        ]

        Enum.each(sensors, fn sensor ->
          case Client.get_state(sensor) do
            {:ok, state} ->
              Logger.info("✅ Found sensor: #{sensor} = #{Map.get(state, "state")}")
            {:error, _reason} ->
              Logger.info("❌ Sensor not found: #{sensor}")
          end
        end)

        Client.disconnect()
        System.halt(0)
      {:error, reason} ->
        Logger.error("Failed: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

TestSensors.main()
