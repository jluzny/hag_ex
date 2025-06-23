defmodule HagEx.Hvac.StateMachine do
  @moduledoc """
  HVAC state machine using Finitomata 0.34.0.

  Manages heating, cooling, and defrost states based on temperature
  conditions and system configuration.
  """

  @fsm """
  initial --> |initialize| idle
  idle --> |start_heating| heating
  idle --> |start_cooling| cooling
  idle --> |start_defrost| defrost
  idle --> |shutdown| stopped
  heating --> |stop_heating| idle
  heating --> |start_defrost| defrost
  heating --> |shutdown| stopped
  cooling --> |stop_cooling| idle
  cooling --> |shutdown| stopped
  defrost --> |complete_defrost| idle
  defrost --> |resume_heating| heating
  defrost --> |shutdown| stopped
  """

  use Finitomata,
    fsm: @fsm,
    # Check conditions every 5 seconds
    timer: 5000,
    auto_terminate: false

  require Logger

  alias HagEx.Config.HvacOptions
  alias HagEx.HomeAssistant.Client

  defstruct [
    :hvac_options,
    :current_temp,
    :outdoor_temp,
    :current_hour,
    :is_weekday,
    :last_defrost,
    :defrost_started
  ]

  @type t :: %__MODULE__{
          hvac_options: HvacOptions.t(),
          current_temp: float() | nil,
          outdoor_temp: float() | nil,
          current_hour: 0..23 | nil,
          is_weekday: boolean() | nil,
          last_defrost: DateTime.t() | nil,
          defrost_started: DateTime.t() | nil
        }

  # State transition handlers using Finitomata 0.34.0 API

  @impl Finitomata
  def on_transition(:initial, :initialize, _event_payload, state_payload) do
    Logger.info("🚀 Initializing HVAC state machine")
    Logger.debug("🔧 System mode: #{state_payload.hvac_options.system_mode}")
    Logger.debug("🏠 Entities configured: #{length(state_payload.hvac_options.hvac_entities)}")
    {:ok, :idle, state_payload}
  end

  @impl Finitomata
  def on_transition(:idle, :start_heating, _event_payload, state_payload) do
    Logger.info("🔥 Starting heating mode")
    Logger.debug("🌡️  Indoor: #{state_payload.current_temp}°C, Outdoor: #{state_payload.outdoor_temp}°C")
    Logger.debug("🎯 Target: #{state_payload.hvac_options.heating.temperature}°C")

    case set_hvac_entities_mode(:heat, state_payload) do
      :ok ->
        {:ok, :heating, state_payload}

      {:error, reason} ->
        Logger.error("Failed to start heating: #{inspect(reason)}")
        {:ok, :idle, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(:idle, :start_cooling, _event_payload, state_payload) do
    Logger.info("❄️  Starting cooling mode")
    Logger.debug("🌡️  Indoor: #{state_payload.current_temp}°C, Outdoor: #{state_payload.outdoor_temp}°C")
    Logger.debug("🎯 Target: #{state_payload.hvac_options.cooling.temperature}°C")

    case set_hvac_entities_mode(:cool, state_payload) do
      :ok ->
        {:ok, :cooling, state_payload}

      {:error, reason} ->
        Logger.error("Failed to start cooling: #{inspect(reason)}")
        {:ok, :idle, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(:heating, :start_defrost, _event_payload, state_payload) do
    Logger.info("🧊 Starting defrost cycle")
    Logger.debug("🌡️  Outdoor: #{state_payload.outdoor_temp}°C")
    Logger.debug("⏰ Duration: #{state_payload.hvac_options.heating.defrost.duration_seconds}s")

    defrost_started = DateTime.utc_now()
    updated_payload = %{state_payload | defrost_started: defrost_started}

    case start_defrost_cycle(updated_payload) do
      :ok ->
        {:ok, :defrost, updated_payload}

      {:error, reason} ->
        Logger.error("Failed to start defrost: #{inspect(reason)}")
        {:ok, :heating, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(:defrost, :complete_defrost, _event_payload, state_payload) do
    Logger.info("Completing defrost cycle")

    last_defrost = DateTime.utc_now()
    updated_payload = %{state_payload | last_defrost: last_defrost, defrost_started: nil}

    case set_hvac_entities_mode(:off, updated_payload) do
      :ok ->
        {:ok, :idle, updated_payload}

      {:error, reason} ->
        Logger.error("Failed to complete defrost: #{inspect(reason)}")
        {:ok, :defrost, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(:idle, :start_defrost, _event_payload, state_payload) do
    Logger.info("Starting defrost cycle from idle: outdoor=#{state_payload.outdoor_temp}°C")

    defrost_started = DateTime.utc_now()
    updated_payload = %{state_payload | defrost_started: defrost_started}

    case start_defrost_cycle(updated_payload) do
      :ok ->
        {:ok, :defrost, updated_payload}

      {:error, reason} ->
        Logger.error("Failed to start defrost from idle: #{inspect(reason)}")
        {:ok, :idle, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(:defrost, :resume_heating, _event_payload, state_payload) do
    Logger.info("Resuming heating after defrost cycle")

    last_defrost = DateTime.utc_now()
    updated_payload = %{state_payload | last_defrost: last_defrost, defrost_started: nil}

    case set_hvac_entities_mode(:heat, updated_payload) do
      :ok ->
        {:ok, :heating, updated_payload}

      {:error, reason} ->
        Logger.error("Failed to resume heating: #{inspect(reason)}")
        {:ok, :defrost, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(from_state, event, _event_payload, state_payload)
      when event in [:stop_heating, :stop_cooling] do
    Logger.info("Stopping #{from_state} mode")

    case set_hvac_entities_mode(:off, state_payload) do
      :ok ->
        {:ok, :idle, state_payload}

      {:error, reason} ->
        Logger.error("Failed to stop #{from_state}: #{inspect(reason)}")
        {:ok, from_state, state_payload}
    end
  end

  @impl Finitomata
  def on_transition(from_state, :shutdown, _event_payload, state_payload) do
    Logger.info("Shutting down HVAC system from #{from_state}")

    case set_hvac_entities_mode(:off, state_payload) do
      :ok ->
        {:ok, :stopped, state_payload}

      {:error, reason} ->
        Logger.error("Failed to shutdown from #{from_state}: #{inspect(reason)}")
        {:ok, from_state, state_payload}
    end
  end

  # Timer callback for periodic condition checking
  @impl Finitomata
  def on_timer(current_state, %__MODULE__{} = state_payload) do
    # Evaluate current conditions and trigger appropriate transitions
    target_event = determine_target_event(state_payload)

    case target_event do
      nil ->
        Logger.debug("⏰ Timer check: no action needed in state #{current_state}")
        {:ok, state_payload}

      event ->
        Logger.info("⏰ Timer triggered transition: #{current_state} → #{event}")
        Logger.debug("🌡️  Conditions: indoor=#{state_payload.current_temp}°C, outdoor=#{state_payload.outdoor_temp}°C")
        _result = Finitomata.transition(self(), event, %{triggered_by: :timer})
        {:ok, state_payload}
    end
  end

  # Optional: Handle entry into states
  @impl Finitomata
  def on_enter(state, _state_payload) do
    Logger.debug("Entered state: #{state}")
    :ok
  end

  # Optional: Handle exit from states  
  @impl Finitomata
  def on_exit(state, _state_payload) do
    Logger.debug("Exited state: #{state}")
    :ok
  end

  # Public API for external temperature updates

  @doc """
  Update temperature conditions and let the timer-based evaluation handle transitions.
  """
  @spec update_conditions(pid(), float() | nil, float() | nil, 0..23, boolean()) :: :ok
  def update_conditions(fsm_pid, current_temp, outdoor_temp, hour, is_weekday) do
    Logger.debug("📊 Updating conditions: indoor=#{current_temp}°C, outdoor=#{outdoor_temp}°C, hour=#{hour}")
    
    # Send state update to the FSM
    GenServer.cast(
      fsm_pid,
      {:update_conditions,
       %{
         current_temp: current_temp,
         outdoor_temp: outdoor_temp,
         current_hour: hour,
         is_weekday: is_weekday
       }}
    )
    :ok
  end

  # Handle state updates via GenServer cast
  def handle_cast({:update_conditions, conditions}, {state, state_payload}) do
    updated_payload = %{
      state_payload
      | current_temp: conditions.current_temp,
        outdoor_temp: conditions.outdoor_temp,
        current_hour: conditions.current_hour,
        is_weekday: conditions.is_weekday
    }

    {:noreply, {state, updated_payload}}
  end

  # Helper functions

  defp determine_target_event(%__MODULE__{} = payload) do
    case Finitomata.state(self()) do
      {:ok, {:initial, _}} ->
        :initialize

      {:ok, {:stopped, _}} ->
        nil

      {:ok, {current_state, _}} ->
        # Check if defrost cycle should be completed based on duration
        if current_state == :defrost and defrost_cycle_completed?(payload) do
          # Decide whether to resume heating or go idle after defrost
          if should_resume_heating_after_defrost?(payload) do
            :resume_heating
          else
            :complete_defrost
          end
        else
          # Normal state machine logic
          active_mode = determine_active_mode(payload)
          
          case active_mode do
            :heat_only ->
              determine_heating_event(current_state, payload)
            
            :cool_only ->
              determine_cooling_event(current_state, payload)
            
            :off ->
              # System should be off - turn off everything
              case current_state do
                :heating -> :stop_heating
                :cooling -> :stop_cooling
                :defrost -> :complete_defrost
                _ -> nil
              end
          end
        end

      _ ->
        nil
    end
  end

  # Determine which mode should be active based on intelligent decision or manual config
  defp determine_active_mode(%__MODULE__{hvac_options: hvac_opts} = payload) do
    case hvac_opts.system_mode do
      # Manual modes - use as configured
      :heat_only -> :heat_only
      :cool_only -> :cool_only
      :off -> :off

      # Auto mode - intelligent decision
      :auto ->
        heating_thresholds = hvac_opts.heating.temperature_thresholds
        cooling_thresholds = hvac_opts.cooling.temperature_thresholds

        # Priority 1: Check if we're in urgent need (very hot/cold)
        cond do
          payload.current_temp < heating_thresholds.indoor_min ->
            # Very cold - need heating if outdoor conditions allow
            if payload.outdoor_temp >= heating_thresholds.outdoor_min and
               payload.outdoor_temp <= heating_thresholds.outdoor_max and
               can_operate_hours?(payload) do
              :heat_only
            else
              :off
            end

          payload.current_temp > cooling_thresholds.indoor_max ->
            # Very hot - need cooling if outdoor conditions allow
            if payload.outdoor_temp >= cooling_thresholds.outdoor_min and
               payload.outdoor_temp <= cooling_thresholds.outdoor_max and
               can_operate_hours?(payload) do
              :cool_only
            else
              :off
            end

          true ->
            # Priority 2: Use outdoor temperature to guide decision
            heating_can_operate = payload.outdoor_temp >= heating_thresholds.outdoor_min and
                                  payload.outdoor_temp <= heating_thresholds.outdoor_max and
                                  can_operate_hours?(payload)
            
            cooling_can_operate = payload.outdoor_temp >= cooling_thresholds.outdoor_min and
                                  payload.outdoor_temp <= cooling_thresholds.outdoor_max and
                                  can_operate_hours?(payload)

            case {heating_can_operate, cooling_can_operate} do
              {true, true} ->
                # Both can operate - use outdoor temperature to decide
                mid_temp = (heating_thresholds.outdoor_max + cooling_thresholds.outdoor_min) / 2.0
                if payload.outdoor_temp <= mid_temp do
                  :heat_only  # Cooler weather - prefer heating
                else
                  :cool_only  # Warmer weather - prefer cooling
                end
              
              {true, false} -> :heat_only  # Only heating can operate
              {false, true} -> :cool_only  # Only cooling can operate
              {false, false} -> :off       # Neither can operate
            end
        end
    end
  end

  defp determine_heating_event(current_state, payload) do
    cond do
      not can_operate_hours?(payload) ->
        case current_state do
          :heating -> :stop_heating
          :defrost -> :complete_defrost
          _ -> nil
        end

      need_defrost?(payload) ->
        case current_state do
          :heating -> :start_defrost
          _ -> nil
        end

      should_heat?(payload) ->
        case current_state do
          :idle -> :start_heating
          :defrost -> nil  # Wait for defrost to complete
          _ -> nil
        end

      true ->
        case current_state do
          :heating -> :stop_heating
          _ -> nil
        end
    end
  end

  defp determine_cooling_event(current_state, payload) do
    cond do
      not can_operate_hours?(payload) ->
        case current_state do
          :cooling -> :stop_cooling
          _ -> nil
        end

      should_cool?(payload) ->
        case current_state do
          :idle -> :start_cooling
          _ -> nil
        end

      true ->
        case current_state do
          :cooling -> :stop_cooling
          _ -> nil
        end
    end
  end

  defp can_operate_hours?(%__MODULE__{hvac_options: hvac_opts} = payload) do
    # Check active hours
    active_hours = hvac_opts.active_hours
    start_hour = if payload.is_weekday, do: active_hours.start_weekday, else: active_hours.start

    payload.current_hour >= start_hour and payload.current_hour <= active_hours.end
  end

  defp should_heat?(%__MODULE__{hvac_options: hvac_opts} = payload) do
    heating_thresholds = hvac_opts.heating.temperature_thresholds

    temp_low = payload.current_temp < heating_thresholds.indoor_min

    outdoor_ok =
      payload.outdoor_temp >= heating_thresholds.outdoor_min and
        payload.outdoor_temp <= heating_thresholds.outdoor_max

    temp_low and outdoor_ok
  end

  defp should_cool?(%__MODULE__{hvac_options: hvac_opts} = payload) do
    cooling_thresholds = hvac_opts.cooling.temperature_thresholds

    temp_high = payload.current_temp > cooling_thresholds.indoor_max

    outdoor_ok =
      payload.outdoor_temp >= cooling_thresholds.outdoor_min and
        payload.outdoor_temp <= cooling_thresholds.outdoor_max

    temp_high and outdoor_ok
  end

  defp need_defrost?(%__MODULE__{hvac_options: hvac_opts} = payload) do
    defrost_config = hvac_opts.heating.defrost
    now = DateTime.utc_now()

    # Only defrost during heating and in cold weather
    case {Finitomata.state(self()), payload.outdoor_temp} do
      {{:ok, {:heating, _}}, outdoor_temp}
      when outdoor_temp <= defrost_config.temperature_threshold ->
        # Check time since last defrost
        case payload.last_defrost do
          nil ->
            true

          last_defrost ->
            DateTime.diff(now, last_defrost, :second) >= defrost_config.period_seconds
        end

      _ ->
        false
    end
  end

  defp set_hvac_entities_mode(mode, %__MODULE__{hvac_options: hvac_opts}) do
    enabled_entities = Enum.filter(hvac_opts.hvac_entities, & &1.enabled)

    results =
      Enum.map(enabled_entities, fn entity ->
        case set_entity_mode(entity, mode, hvac_opts) do
          :ok -> :ok
          {:error, _} -> :error
        end
      end)

    case Enum.all?(results, &(&1 == :ok)) do
      true -> :ok
      false -> {:error, :partial_failure}
    end
  end

  defp set_entity_mode(entity, :heat, hvac_opts) do
    with {:ok, _} <-
           Client.call_service("climate", "set_hvac_mode", %{
             "entity_id" => entity.entity_id,
             "hvac_mode" => "heat"
           }),
         {:ok, _} <-
           Client.call_service("climate", "set_preset_mode", %{
             "entity_id" => entity.entity_id,
             "preset_mode" => hvac_opts.heating.preset_mode
           }),
         {:ok, _} <-
           Client.call_service("climate", "set_temperature", %{
             "entity_id" => entity.entity_id,
             "temperature" => hvac_opts.heating.temperature
           }) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to set heating mode for #{entity.entity_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp set_entity_mode(entity, :cool, hvac_opts) do
    with {:ok, _} <-
           Client.call_service("climate", "set_hvac_mode", %{
             "entity_id" => entity.entity_id,
             "hvac_mode" => "cool"
           }),
         {:ok, _} <-
           Client.call_service("climate", "set_preset_mode", %{
             "entity_id" => entity.entity_id,
             "preset_mode" => hvac_opts.cooling.preset_mode
           }),
         {:ok, _} <-
           Client.call_service("climate", "set_temperature", %{
             "entity_id" => entity.entity_id,
             "temperature" => hvac_opts.cooling.temperature
           }) do
      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to set cooling mode for #{entity.entity_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp set_entity_mode(entity, :off, _hvac_opts) do
    case Client.call_service("climate", "set_hvac_mode", %{
           "entity_id" => entity.entity_id,
           "hvac_mode" => "off"
         }) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to set off mode for #{entity.entity_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp start_defrost_cycle(%__MODULE__{hvac_options: hvac_opts}) do
    # For defrost, only entities with defrost=true are set to cool mode
    defrost_entities =
      Enum.filter(hvac_opts.hvac_entities, fn entity ->
        entity.enabled and entity.defrost
      end)

    results =
      Enum.map(defrost_entities, fn entity ->
        case Client.call_service("climate", "set_hvac_mode", %{
          "entity_id" => entity.entity_id,
          "hvac_mode" => "cool"
        }) do
          {:ok, _} -> :ok
          {:error, _} -> :error
        end
      end)

    case Enum.all?(results, &(&1 == :ok)) do
      true -> :ok
      false -> {:error, :defrost_start_failed}
    end
  end

  # Helper functions for defrost cycle completion and heating resumption
  
  defp defrost_cycle_completed?(%__MODULE__{hvac_options: hvac_opts, defrost_started: defrost_started}) do
    case defrost_started do
      nil -> false
      start_time ->
        duration_seconds = hvac_opts.heating.defrost.duration_seconds
        DateTime.diff(DateTime.utc_now(), start_time, :second) >= duration_seconds
    end
  end
  
  defp should_resume_heating_after_defrost?(%__MODULE__{} = payload) do
    # Resume heating if:
    # 1. We can operate (hours and outdoor conditions allow)
    # 2. Temperature is still too low
    can_operate_hours?(payload) and should_heat?(payload)
  end
end
