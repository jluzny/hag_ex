
#!/usr/bin/env elixir

# Test REST API Directly Script
# Tests Home Assistant REST API calls directly without using the HAG client
# Useful for debugging REST API URL construction and authentication issues

defmodule TestRestAPI do
  require Logger
  alias Jason

  def main(args) do
    if Enum.empty?(args) do
      IO.puts "Usage: ./test_rest_api.exs <entity_id>"
      System.halt(1)
    end

    entity_id = hd(args)

    # Test REST API directly
    token = System.get_env("HASS_HassOptions__Token")
    rest_url = "http://192.168.0.204:8123/api"

    if is_nil(token) do
      Logger.error("HASS_HassOptions__Token environment variable not set.")
      System.halt(1)
    end

    Logger.info("Testing #{entity_id}...")

    url = "#{rest_url}/states/#{entity_id}"
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.get(url, headers: headers) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, data} ->
            state_value = Map.get(data, "state")
            unit = Map.get(Map.get(data, "attributes", %{}), "unit_of_measurement", "")
            Logger.info("✅ Success: #{entity_id} = #{state_value} #{unit}")
            Logger.info("  Attributes: #{inspect(Map.get(data, "attributes"))}")
            System.halt(0)
          {:error, reason} ->
            Logger.error("❌ Failed: Error decoding JSON: #{inspect(reason)}")
            System.halt(1)
        end
      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("❌ Failed: #{status} - #{body}")
        System.halt(1)
      {:error, reason} ->
        Logger.error("❌ Error: #{inspect(reason)}")
        System.halt(1)
    end
  end
end

TestRestAPI.main(System.argv())
