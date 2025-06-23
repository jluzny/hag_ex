defmodule HagEx.Hvac.Agent do
  @moduledoc """
  Jido Agent for autonomous HVAC control using Jido 1.2.0.

  This agent orchestrates temperature monitoring and HVAC control
  through composable actions and intelligent decision making.
  """

  use Jido.Agent,
    name: "hvac_controller",
    description: "Autonomous HVAC control agent for Home Assistant integration",
    actions: [
      HagEx.Hvac.Actions.TemperatureMonitor,
      HagEx.Hvac.Actions.HvacControl,
      HagEx.Hvac.Actions.SensorDataProcessor
    ]

  require Logger
  alias HagEx.Hvac.Actions.{TemperatureMonitor, HvacControl, SensorDataProcessor}
  alias HagEx.Hvac.Sensors.TemperatureSensor

  # No custom mount implementation - let Jido handle it

  @impl true
  def handle_info(:check_temperature, state) do
    Logger.debug("Agent triggered temperature check")

    # Execute temperature monitoring action
    run_action_async(TemperatureMonitor, %{
      temp_sensor: state.hvac_options.temp_sensor,
      outdoor_sensor: "sensor.openweathermap_temperature",
      state_machine_pid: state.state_machine_pid,
      check_interval: state.check_interval
    })

    # Schedule next check
    schedule_next_check(state.check_interval)

    {:noreply, state}
  end

  @impl true
  def handle_info({:action_completed, TemperatureMonitor, result}, state) do
    Logger.debug("Temperature monitoring completed: #{inspect(result)}")

    case result do
      {:ok, %{conditions_updated: true}} ->
        # Conditions were updated, state machine will handle transitions
        :ok

      {:error, reason} ->
        Logger.warning("Temperature monitoring failed: #{inspect(reason)}")

        # Log the failure
        run_action_async(Jido.Actions.Core.Log, %{
          level: :warn,
          message: "Temperature monitoring failed: #{inspect(reason)}"
        })
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:action_completed, HvacControl, result}, state) do
    Logger.debug("HVAC control completed: #{inspect(result)}")

    case result do
      {:ok, %{all_successful: true}} ->
        Logger.info("HVAC control successful")

      {:ok, %{partial_success: true}} ->
        Logger.warning("HVAC control partially successful")

      {:error, reason} ->
        Logger.error("HVAC control failed: #{inspect(reason)}")
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:temperature_signal, signal_data}, state) do
    Logger.debug("Agent received temperature signal: #{inspect(signal_data)}")

    # Process temperature data through sensor data processor action
    run_action_async(SensorDataProcessor, %{
      sensor_signals: [%{topic: "hvac.temperature.updated", payload: signal_data}],
      hvac_options: state.hvac_options,
      state_machine_pid: state.state_machine_pid,
      decision_window: state.check_interval
    })

    {:noreply, state}
  end

  @impl true
  def handle_info({:state_machine_event, event, payload}, state) do
    Logger.debug("Received state machine event: #{event}")

    case event do
      :heating_requested ->
        control_hvac(:heat, state, payload)

      :cooling_requested ->
        control_hvac(:cool, state, payload)

      :hvac_off_requested ->
        control_hvac(:off, state, payload)

      _ ->
        Logger.debug("Unhandled state machine event: #{event}")
    end

    {:noreply, state}
  end

  # Public API

  @doc """
  Manually trigger a temperature check.
  """
  def trigger_temperature_check(agent_pid \\ __MODULE__) do
    send(agent_pid, :check_temperature)
  end

  @doc """
  Control HVAC system with specific mode.
  """
  def control_hvac_mode(agent_pid \\ __MODULE__, mode, options \\ %{}) do
    send(agent_pid, {:control_hvac, mode, options})
  end

  # Private helper functions

  defp start_temperature_sensor(state) do
    agent_pid = self()

    # Configure sensor to send signals to this agent
    sensor_config = [
      id: "hvac_temperature_sensor",
      entity_id: state.hvac_options.temp_sensor,
      poll_interval: state.check_interval,
      threshold_delta: state.sensor_threshold,
      outdoor_sensor: "sensor.openweathermap_temperature",
      target:
        {:function,
         fn signal ->
           send(agent_pid, {:temperature_signal, signal.data})
         end}
    ]

    case TemperatureSensor.start_link(sensor_config) do
      {:ok, sensor_pid} ->
        Logger.info("Temperature sensor started: #{inspect(sensor_pid)}")
        {:ok, sensor_pid}

      {:error, reason} ->
        Logger.error("Failed to start temperature sensor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp schedule_next_check(interval_ms) do
    Process.send_after(self(), :check_temperature, interval_ms)
  end

  defp control_hvac(mode, state, payload) do
    hvac_params = build_hvac_params(mode, state.hvac_options, payload)

    Logger.info("Agent controlling HVAC: #{mode} mode")

    run_action_async(HvacControl, hvac_params)
  end

  defp build_hvac_params(:heat, hvac_options, _payload) do
    %{
      mode: :heat,
      entities: hvac_options.hvac_entities,
      temperature: hvac_options.heating.temperature,
      preset_mode: hvac_options.heating.preset_mode
    }
  end

  defp build_hvac_params(:cool, hvac_options, _payload) do
    %{
      mode: :cool,
      entities: hvac_options.hvac_entities,
      temperature: hvac_options.cooling.temperature,
      preset_mode: hvac_options.cooling.preset_mode
    }
  end

  defp build_hvac_params(:off, hvac_options, _payload) do
    %{
      mode: :off,
      entities: hvac_options.hvac_entities
    }
  end

  defp run_action_async(action_module, params) do
    Task.start(fn ->
      case action_module.run(params, %{}) do
        {:ok, result} ->
          send(self(), {:action_completed, action_module, {:ok, result}})

        {:error, reason} ->
          send(self(), {:action_completed, action_module, {:error, reason}})
      end
    end)
  end
end
