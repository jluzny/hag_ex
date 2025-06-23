defmodule HagEx do
  @moduledoc """
  HAG (Home Assistant aGentic automation) Elixir - HVAC Control System

  An intelligent HVAC automation system that integrates with Home Assistant
  to provide smart heating, cooling, and defrost management based on 
  temperature conditions and configurable schedules.

  ## Features

  - Intelligent heating/cooling mode selection
  - Automatic defrost cycle management  
  - Configurable temperature thresholds and active hours
  - Real-time Home Assistant integration via WebSocket
  - Fault-tolerant operation with OTP supervision
  - Workflow-based orchestration with Jido
  - State machine logic with Finitomata

  ## Usage

      # Get current system status
      HagEx.status()
      
      # Manually trigger temperature evaluation
      HagEx.trigger_evaluation()
      
      # Get configuration info
      HagEx.config_info()
  """

  alias HagEx.Hvac.Controller

  @doc """
  Get the current HVAC system status.

  Returns information about the state machine, monitoring workflows,
  and system configuration.
  """
  @spec status() :: map()
  def status do
    Controller.get_status()
  end

  @doc """
  Manually trigger a temperature evaluation and state update.

  Useful for testing or forcing an immediate system check.
  """
  @spec trigger_evaluation() :: :ok
  def trigger_evaluation do
    Controller.trigger_evaluation()
  end

  @doc """
  Get basic configuration information.
  """
  @spec config_info() :: map()
  def config_info do
    config_file = Application.get_env(:hag_ex, :config_file, "config/hvac_config.yaml")

    %{
      config_file: config_file,
      environment: Application.get_env(:hag_ex, :environment, :dev),
      version: Application.spec(:hag_ex, :vsn) |> to_string()
    }
  end

  @doc """
  Display system information and status in a formatted way.
  """
  @spec info() :: :ok
  def info do
    IO.puts("\n🏠 HAG HVAC Control System")
    IO.puts("=" |> String.duplicate(40))

    # Configuration info
    config = config_info()
    IO.puts("📁 Config: #{config.config_file}")
    IO.puts("🌍 Environment: #{config.environment}")
    IO.puts("📦 Version: #{config.version}")

    # System status
    IO.puts("\n📊 System Status:")

    case status() do
      %{state_machine: %{current_state: state, status: :running}} ->
        IO.puts("🤖 State Machine: #{state} (running)")

      %{state_machine: %{status: status}} ->
        IO.puts("🤖 State Machine: #{status}")

      _ ->
        IO.puts("🤖 State Machine: unknown")
    end

    IO.puts("\n✅ Use HagEx.status() for detailed information")
    IO.puts("🔄 Use HagEx.trigger_evaluation() to force a check")
    :ok
  end
end
