

#!/usr/bin/env elixir

# List Home Assistant Entities Script
# Lists available entities by type to discover what sensors are available

defmodule ListEntities do
  require Logger
  alias HagEx.HomeAssistant.Client
  alias Jason

  def main() do
    # Home Assistant details
    token = System.get_env("HASS_HassOptions__Token")
    rest_url = "http://192.168.0.204:8123/api"

    if is_nil(token) do
      Logger.error("HASS_HassOptions__Token environment variable not set.")
      System.halt(1)
    end

    # Try some common entity prefixes to see what's available
    entity_prefixes = ["sensor", "climate", "weather", "sun"]

    Enum.each(entity_prefixes, fn prefix ->
      url = "#{rest_url}/states"
      headers = [
        {"Authorization", "Bearer #{token}"},
        {"Content-Type", "application/json"}
      ]

      case Req.get(url, headers: headers) do
        {:ok, %Req.Response{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, states} ->
              filtered_states = Enum.filter(states, fn state ->
                String.starts_with?(Map.get(state, "entity_id", ""), prefix) and
                (String.contains?(Map.get(state, "entity_id", ""), "temperature") or
                 String.contains?(Map.get(state, "entity_id", ""), "temp") or
                 prefix == "climate")
              end)

              Logger.info("\n#{String.upcase(prefix)} entities:")
              Enum.take(filtered_states, 5)
              |> Enum.each(fn state ->
                entity_id = Map.get(state, "entity_id")
                state_value = Map.get(state, "state")
                unit = Map.get(Map.get(state, "attributes", %{}), "unit_of_measurement", "")
                Logger.info("  #{entity_id}: #{state_value} #{unit}")
              end)
              if Enum.count(filtered_states) > 5 do
                Logger.info("  ... and #{Enum.count(filtered_states) - 5} more")
              end
            {:error, reason} ->
              Logger.error("Error decoding JSON: #{inspect(reason)}")
          end
        {:ok, %Req.Response{status: status, body: body}} ->
          Logger.error("Error fetching entities: #{status} - #{body}")
        {:error, reason} ->
          Logger.error("Error fetching entities: #{inspect(reason)}")
      end
    end)
    System.halt(0)
  end
end

ListEntities.main()
