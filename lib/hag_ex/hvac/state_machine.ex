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
    Logger.info("Initializing HVAC state machine")
    {:ok, :idle, state_payload}
  end

  @impl Finitomata
  def on_transition(:idle, :start_heating, _event_payload, state_payload) do
    Logger.info(
      "Starting heating mode: temp=#{state_payload.current_temp}°C, outdoor=#{state_payload.outdoor_temp}°C"
    )

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
    Logger.info(
      "Starting cooling mode: temp=#{state_payload.current_temp}°C, outdoor=#{state_payload.outdoor_temp}°C"
    )

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
    Logger.info("Starting defrost cycle: outdoor=#{state_payload.outdoor_temp}°C")

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
        {:ok, state_payload}

      event ->
        Logger.debug("Timer triggered event: #{event} from state #{current_state}")
        Finitomata.transition(self(), event, %{triggered_by: :timer})
        {:ok, state_payload}
    end
  end

  # Optional: Handle entry into states
  @impl Finitomata
  def on_enter(state, state_payload) do
    Logger.debug("Entered state: #{state}")
    {:ok, state_payload}
  end

  # Optional: Handle exit from states  
  @impl Finitomata
  def on_exit(state, state_payload) do
    Logger.debug("Exited state: #{state}")
    {:ok, state_payload}
  end

  # Public API for external temperature updates

  @doc """
  Update temperature conditions and let the timer-based evaluation handle transitions.
  """
  @spec update_conditions(pid(), float(), float(), 0..23, boolean()) :: :ok
  def update_conditions(fsm_pid, current_temp, outdoor_temp, hour, is_weekday) do
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
        cond do
          not can_operate?(payload) ->
            case current_state do
              :heating -> :stop_heating
              :cooling -> :stop_cooling
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
              _ -> nil
            end

          should_cool?(payload) ->
            case current_state do
              :idle -> :start_cooling
              _ -> nil
            end

          true ->
            case current_state do
              :heating -> :stop_heating
              :cooling -> :stop_cooling
              _ -> nil
            end
        end

      _ ->
        nil
    end
  end

  defp can_operate?(%__MODULE__{hvac_options: hvac_opts} = payload) do
    # Check active hours
    active_hours = hvac_opts.active_hours
    start_hour = if payload.is_weekday, do: active_hours.start, else: active_hours.start_weekday

    hours_ok = payload.current_hour >= start_hour and payload.current_hour <= active_hours.end

    # Check outdoor temperature (use heating limits as general operability check)
    outdoor_ok = payload.outdoor_temp >= hvac_opts.heating.temperature_thresholds.outdoor_min

    hours_ok and outdoor_ok
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
        set_entity_mode(entity, mode, hvac_opts)
      end)

    case Enum.all?(results, &(&1 == :ok)) do
      true -> :ok
      false -> {:error, :partial_failure}
    end
  end

  defp set_entity_mode(entity, :heat, hvac_opts) do
    with :ok <-
           Client.call_service("climate", "set_hvac_mode", %{
             "entity_id" => entity.entity_id,
             "hvac_mode" => "heat"
           }),
         :ok <-
           Client.call_service("climate", "set_preset_mode", %{
             "entity_id" => entity.entity_id,
             "preset_mode" => hvac_opts.heating.preset_mode
           }),
         :ok <-
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
    with :ok <-
           Client.call_service("climate", "set_hvac_mode", %{
             "entity_id" => entity.entity_id,
             "hvac_mode" => "cool"
           }),
         :ok <-
           Client.call_service("climate", "set_preset_mode", %{
             "entity_id" => entity.entity_id,
             "preset_mode" => hvac_opts.cooling.preset_mode
           }),
         :ok <-
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
      :ok ->
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
        Client.call_service("climate", "set_hvac_mode", %{
          "entity_id" => entity.entity_id,
          "hvac_mode" => "cool"
        })
      end)

    case Enum.all?(results, &(&1 == :ok)) do
      true -> :ok
      false -> {:error, :defrost_start_failed}
    end
  end

  # Defrost completion is now handled by the timer callback
  # which checks if defrost duration has elapsed
end
