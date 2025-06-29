
#!/usr/bin/env elixir

# Call Home Assistant Service Script
# Calls a Home Assistant service using the REST API.

defmodule CallService do
  require Logger
  alias Jason

  def main(args) do
    if Enum.empty?(args) do
      IO.puts "Usage: ./call_service.exs <domain>.<service> [--entity_id <entity_id>] [key=value ...]"
      System.halt(1)
    end

    [service | rest_args] = args
    [domain, service_name] = String.split(service, ".")

    if is_nil(domain) or is_nil(service_name) do
      IO.puts "Invalid service format. Use <domain>.<service>"
      System.halt(1)
    end

    service_data = parse_service_data(rest_args)

    # Home Assistant details
    token = System.get_env("HASS_HassOptions__Token")
    rest_url = "http://192.168.0.204:8123/api"

    if is_nil(token) do
      Logger.error("HASS_HassOptions__Token environment variable not set.")
      System.halt(1)
    end

    Logger.info("Calling service #{domain}.#{service_name} with data: #{inspect(service_data)}")

    url = "#{rest_url}/services/#{domain}/#{service_name}"
    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Content-Type", "application/json"}
    ]

    case Req.post(url, headers: headers, body: Jason.encode!(service_data)) do
      {:ok, %Req.Response{status: 200}} ->
        Logger.info("✅ Service #{domain}.#{service_name} called successfully.")
        System.halt(0)
      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("❌ Failed to call service: #{status} - #{body}")
        System.halt(1)
      {:error, reason} ->
        Logger.error("❌ Error: #{inspect(reason)}")
        System.halt(1)
    end
  end

  defp parse_service_data(args) do
    parse_service_data_recursive(args, %{})
  end

  defp parse_service_data_recursive([], acc), do: acc
  defp parse_service_data_recursive([arg | rest], acc) do
    cond do
      String.starts_with?(arg, "--") and String.contains?(arg, "=") ->
        [key_with_dashes, value] = String.split(arg, "=", parts: 2)
        key = String.replace(key_with_dashes, "--", "") |> String.replace("-", "_")
        parse_service_data_recursive(rest, Map.put(acc, String.to_atom(key), value))
      String.starts_with?(arg, "--") ->
        key = String.replace(arg, "--", "") |> String.replace("-", "_")
        # Check if the next argument is a value or another flag
        if length(rest) > 0 and not String.starts_with?(hd(rest), "--") and not String.contains?(hd(rest), "=") do
          value = hd(rest)
          parse_service_data_recursive(tl(rest), Map.put(acc, String.to_atom(key), value))
        else
          parse_service_data_recursive(rest, Map.put(acc, String.to_atom(key), true))
        end
      String.contains?(arg, "=") ->
        [key, value] = String.split(arg, "=", parts: 2)
        parse_service_data_recursive(rest, Map.put(acc, String.to_atom(key), value))
      true ->
        Logger.warning("Skipping unparseable argument: #{arg}")
        parse_service_data_recursive(rest, acc)
    end
  end
end

CallService.main(System.argv())
