
#!/usr/bin/env elixir

# Check HVAC Status Script
# Checks the current status of all HVAC entities

defmodule CheckHvacStatus do
  require Logger
  alias HagEx.HomeAssistant.Client
  alias HagEx.Config

  def main() do
    # Load configuration
    config_path = "/home/jiri/dev/ha/hag_ex/config/hvac_config_dev.yaml"
    case Config.load(config_path) do
      {:ok, config} ->
        hvac_entities = Enum.map(config.hvac_options.hvac_entities, &(&1.entity_id))

        Logger.info("🏠 HVAC Entity Status Check")
        Logger.info("============================")

        # Start Home Assistant Client
        case Client.start_link(config.hass_options) do
          {:ok, client_pid} ->
            Enum.each(hvac_entities, fn entity_id ->
              case Client.get_state(entity_id, client_pid) do
                {:ok, state} ->
                  Logger.info("#{entity_id}:")
                  Logger.info("  State: #{Map.get(state, "state")}")
                  Logger.info("  Temperature: #{Map.get(state, "attributes", %{})["temperature"] || "N/A"}°C")
                  Logger.info("  HVAC Mode: #{Map.get(state, "attributes", %{})["hvac_mode"] || "N/A"}")
                  Logger.info("  Preset: #{Map.get(state, "attributes", %{})["preset_mode"] || "N/A"}°C")
                  Logger.info("  Current Temp: #{Map.get(state, "attributes", %{})["current_temperature"] || "N/A"}°C")
                  Logger.info("")
                {:error, reason} ->
                  Logger.error("❌ Error checking #{entity_id}: #{inspect(reason)}")
              end
            end)
            Client.disconnect(client_pid)
            System.halt(0)
          {:error, reason} ->
            Logger.error("❌ Failed to start Home Assistant Client: #{inspect(reason)}")
            System.halt(1)
      {:error, reason} ->
        Logger.error("❌ Failed to load configuration: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

CheckHvacStatus.main()
