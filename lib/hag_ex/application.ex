defmodule HagEx.Application do
  @moduledoc """
  Main application module for HAG (Home Assistant aGentic automation) Elixir.

  Starts the supervision tree for the HVAC automation system.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Check if application should start (disable for tests)
    if Application.get_env(:hag_ex, :start_application, true) do
      Logger.info("Starting HAG HVAC application")

      # Load configuration
      config_file = Application.get_env(:hag_ex, :config_file, "config/hvac_config.yaml")

      case HagEx.Config.load(config_file) do
        {:ok, config} ->
          start_with_config(config)

        {:error, reason} ->
          Logger.error("Failed to load configuration: #{inspect(reason)}")
          {:error, reason}
      end
    else
      Logger.info("HAG HVAC application startup disabled for testing")
      # Return a minimal supervision tree for tests
      Supervisor.start_link([], strategy: :one_for_one, name: HagEx.Supervisor)
    end
  end

  defp start_with_config(config) do
    children = [
      # Home Assistant WebSocket client
      {HagEx.HomeAssistant.Client, config.hass_options},

      # HVAC controller (includes state machine and workflows)
      {HagEx.Hvac.Controller, config},

      # Optional: Add telemetry and monitoring
      {Task.Supervisor, name: HagEx.TaskSupervisor}
    ]

    # Supervisor strategy: restart child processes if they crash
    opts = [
      strategy: :one_for_one,
      name: HagEx.Supervisor,
      max_restarts: 5,
      max_seconds: 60
    ]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("HAG HVAC application started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start HAG HVAC application: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
