defmodule HagEx.Hvac.Controller do
  @moduledoc """
  Main HVAC controller using Jido 1.2.0 Agents.

  Orchestrates temperature monitoring, state evaluation, and HVAC control
  through intelligent agent-based automation.
  """

  use GenServer
  require Logger

  alias HagEx.Config
  alias HagEx.HomeAssistant.Client
  alias HagEx.Hvac.StateMachine
  alias HagEx.Hvac.Agent, as: HvacAgent

  defstruct [
    :config,
    :state_machine_pid,
    :hvac_agent_pid
  ]

  @type t :: %__MODULE__{
          config: Config.t(),
          state_machine_pid: pid(),
          hvac_agent_pid: pid() | nil
        }

  # GenServer API

  @doc """
  Start the HVAC controller with the given configuration.
  """
  @spec start_link(Config.t()) :: GenServer.on_start()
  def start_link(%Config{} = config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @doc """
  Get the current HVAC system status.
  """
  @spec get_status() :: map()
  def get_status do
    GenServer.call(__MODULE__, :get_status)
  end

  @doc """
  Manually trigger a temperature check and state evaluation.
  """
  @spec trigger_evaluation() :: :ok
  def trigger_evaluation do
    GenServer.cast(__MODULE__, :trigger_evaluation)
  end

  # GenServer callbacks

  @impl GenServer
  def init(%Config{} = config) do
    Logger.info("🎮 Starting HVAC controller with Jido 1.2.0")
    Logger.debug("🔧 HVAC entities to manage: #{length(config.hvac_options.hvac_entities)}")
    Logger.debug("🌡️  Temperature sensor: #{config.hvac_options.temp_sensor}")
    Logger.debug("⚙️  System mode: #{config.hvac_options.system_mode}")

    # Start the HVAC state machine
    Logger.debug("🔄 Starting Finitomata state machine...")
    {:ok, state_machine_pid} = start_state_machine(config.hvac_options)
    Logger.debug("✅ State machine started with PID: #{inspect(state_machine_pid)}")

    # Start the Jido HVAC agent
    Logger.debug("🤖 Starting Jido HVAC agent...")
    {:ok, hvac_agent_pid} = start_hvac_agent(config, state_machine_pid)
    Logger.debug("✅ HVAC agent started with PID: #{inspect(hvac_agent_pid)}")

    state = %__MODULE__{
      config: config,
      state_machine_pid: state_machine_pid,
      hvac_agent_pid: hvac_agent_pid
    }

    # Schedule Home Assistant event subscription after initialization
    Logger.debug("📅 Scheduling Home Assistant event subscription in 1 second")
    Process.send_after(self(), :subscribe_to_events, 1000)

    Logger.info("✅ HVAC controller started successfully")
    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      state_machine: get_state_machine_status(state.state_machine_pid),
      hvac_agent: get_agent_status(state.hvac_agent_pid),
      config: %{
        temp_sensor: state.config.hvac_options.temp_sensor,
        system_mode: state.config.hvac_options.system_mode,
        entities_count: length(state.config.hvac_options.hvac_entities)
      }
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast(:trigger_evaluation, state) do
    # Use the Jido agent to trigger temperature check
    HvacAgent.trigger_temperature_check(state.hvac_agent_pid)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:subscribe_to_events, state) do
    # Subscribe to Home Assistant events
    :ok = Client.subscribe_events()
    Logger.info("Successfully subscribed to Home Assistant events")

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:state_changed, event}, state) do
    # Handle Home Assistant state change events
    case extract_temperature_event(event, state.config.hvac_options.temp_sensor) do
      {:ok, temp_data} ->
        # Send the temperature signal to the HVAC agent for processing
        send(state.hvac_agent_pid, {:temperature_signal, temp_data})

      :ignore ->
        # Not a temperature sensor event we care about
        :ok
    end

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:workflow_completed, workflow_type, result}, state) do
    Logger.debug("Workflow #{workflow_type} completed: #{inspect(result)}")
    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:workflow_failed, workflow_type, error}, state) do
    Logger.error("Workflow #{workflow_type} failed: #{inspect(error)}")
    {:noreply, state}
  end

  # Private helper functions

  defp start_state_machine(hvac_options) do
    initial_payload = %StateMachine{hvac_options: hvac_options}
    StateMachine.start_link(payload: initial_payload, name: StateMachine)
  end

  defp start_hvac_agent(config, state_machine_pid) do
    # For Jido agents, pass the configuration directly
    _initial_state = %{
      hvac_options: config.hvac_options,
      state_machine_pid: state_machine_pid,
      monitoring_enabled: true,
      sensor_polling: true,
      check_interval: config.hass_options.state_check_interval,
      sensor_threshold: 0.3
    }

    case HvacAgent.start_link() do
      {:ok, agent_pid} ->
        Logger.info("HVAC Jido agent started successfully")
        {:ok, agent_pid}

      {:error, reason} ->
        Logger.error("Failed to start HVAC agent: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_agent_status(agent_pid) when is_pid(agent_pid) do
    if Process.alive?(agent_pid) do
      %{status: :running, pid: agent_pid}
    else
      %{status: :dead, pid: agent_pid}
    end
  end

  defp get_agent_status(nil), do: %{status: :not_started}

  defp extract_temperature_event(event, target_sensor) do
    with %{"data" => %{"entity_id" => entity_id, "new_state" => new_state}} <- event,
         true <- entity_id == target_sensor,
         %{"state" => temp_str} <- new_state,
         {temp, ""} <- Float.parse(temp_str),
         {:ok, outdoor_temp} <- get_outdoor_temperature() do
      now = DateTime.utc_now()

      {:ok,
       %{
         temperature: temp,
         outdoor_temperature: outdoor_temp,
         timestamp: now,
         hour: now.hour,
         is_weekday: Date.day_of_week(now) <= 5
       }}
    else
      _ -> :ignore
    end
  end

  @spec get_outdoor_temperature() :: {:ok, float()} | {:error, term()}
  defp get_outdoor_temperature do
    # Get outdoor temperature from Home Assistant
    case Client.get_state("sensor.openweathermap_temperature") do
      {:ok, %{"state" => temp_str}} ->
        case Float.parse(temp_str) do
          {temp, ""} -> {:ok, temp}
          _ -> {:error, :invalid_temperature_format}
        end

      {:ok, nil} ->
        {:error, :sensor_not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_state_machine_status(state_machine_pid) do
    try do
      case Finitomata.state(state_machine_pid) do
        {:ok, {current_state, _payload}} ->
          %{current_state: current_state, status: :running}

        {:error, reason} ->
          %{status: :error, reason: reason}
      end
    catch
      :exit, reason ->
        %{status: :dead, reason: reason}
    end
  end
end
