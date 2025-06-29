

#!/usr/bin/env elixir

# Home Assistant Connection Test Script
# Tests both WebSocket and REST API connectivity to Home Assistant

defmodule TestHAConnection do
  require Logger
  alias HagEx.HomeAssistant.Client
  alias Jason

  def main() do
    token = System.get_env("HASS_HassOptions__Token")
    rest_url = "http://192.168.0.204:8123/api"

    if is_nil(token) do
      Logger.error("HASS_HassOptions__Token environment variable not set.")
      System.halt(1)
    end

    Logger.info("🏠 Home Assistant Connection Test\n")

    # Test 1: Direct REST API
    Logger.info("📡 Testing REST API directly...")
    case Req.get("#{rest_url}/states", headers: [{"Authorization", "Bearer #{token}"}, {"Content-Type", "application/json"}]) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, states} ->
            temperature_sensors = Enum.filter(states, fn state ->
              String.contains?(Map.get(state, "entity_id", ""), "temperature") or
              String.contains?(Map.get(state, "entity_id", ""), "temp")
            end)

            Logger.info("✅ REST API working - Found #{Enum.count(temperature_sensors)} temperature sensors")
            Enum.take(temperature_sensors, 5)
            |> Enum.each(fn sensor ->
              entity_id = Map.get(sensor, "entity_id")
              state_value = Map.get(sensor, "state")
              unit = Map.get(Map.get(sensor, "attributes", %{}), "unit_of_measurement", "")
              Logger.info("   #{entity_id}: #{state_value} #{unit}")
            end)
          {:error, reason} ->
            Logger.error("❌ REST API failed: Error decoding JSON: #{inspect(reason)}")
        end
      {:ok, %Req.Response{status: status}} ->
        Logger.error("❌ REST API failed: #{status}")
      {:error, reason} ->
        Logger.error("❌ REST API error: #{inspect(reason)}")
    end

    Logger.info("\n🔌 Testing WebSocket connection...")

    # Test 2: WebSocket via HAG client
    case Client.connect() do
      :ok ->
        Logger.info("✅ WebSocket connected and authenticated")

        # Test specific sensors
        sensors = [
          "sensor.1st_floor_hall_multisensor_temperature",
          "sensor.openweathermap_temperature"
        ]

        Enum.each(sensors, fn sensor ->
          case Client.get_state(sensor) do
            {:ok, state} ->
              unit = Map.get(Map.get(state, "attributes", %{}), "unit_of_measurement", "")
              Logger.info("✅ #{sensor}: #{Map.get(state, "state")} #{unit}")
            {:error, reason} ->
              Logger.error("❌ #{sensor}: #{inspect(reason)}")
          end
        end)

        Client.disconnect()
        Logger.info("✅ WebSocket disconnected cleanly")
      {:error, reason} ->
        Logger.error("❌ WebSocket test failed: #{inspect(reason)}")
    end

    Logger.info("\n🎯 Connection test complete")
    System.halt(0)
  end
end

TestHAConnection.main()
