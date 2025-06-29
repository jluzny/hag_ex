

#!/usr/bin/env elixir

# WebSocket Debug Script
# Tests WebSocket connection and authentication flow step-by-step
# Useful for debugging WebSocket timing and authentication issues

defmodule DebugWebSocket do
  require Logger
  alias HagEx.HomeAssistant.Client
  alias HagEx.Config

  def main() do
    Logger.info("🔌 WebSocket Connection Debug\n")

    # Load configuration
    config_path = "/home/jiri/dev/ha/hag_ex/config/hvac_config_dev.yaml"
    case Config.load(config_path) do
      {:ok, config} ->
        Logger.info("Step 1: Connecting to WebSocket...")
        case Client.connect() do
          :ok ->
            Logger.info("✅ WebSocket connected and authenticated")

            Logger.info("\nStep 2: Testing connection status...")
            Logger.info("Connected: #{Client.connected?()}")

            Logger.info("\nStep 3: Getting connection stats...")
            stats = Client.get_stats()
            Logger.info("Connection stats: #{inspect(stats)}")

            Logger.info("\nStep 4: Testing sensor access...")
            # Test specific sensors
            sensors = [
              "sensor.1st_floor_hall_multisensor_temperature",
              "sensor.openweathermap_temperature"
            ]

            Enum.each(sensors, fn sensor ->
              case Client.get_state(sensor) do
                {:ok, state} ->
                  Logger.info("✅ #{sensor}: #{Map.get(state, "state")}°C")
                {:error, reason} ->
                  Logger.info("❌ #{sensor} error: #{inspect(reason)}")
              end
            end)

            Logger.info("\nStep 5: Disconnecting...")
            Client.disconnect()
            Logger.info("✅ Disconnected cleanly")
            System.halt(0)
          {:error, reason} ->
            Logger.error("❌ WebSocket debug failed: #{inspect(reason)}")
            System.halt(1)
        end
      {:error, reason} ->
        Logger.error("❌ Failed to load configuration: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

DebugWebSocket.main()

