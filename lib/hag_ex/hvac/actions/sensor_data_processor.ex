defmodule HagEx.Hvac.Actions.SensorDataProcessor do
  @moduledoc """
  Jido Action for processing sensor data and making intelligent HVAC decisions.

  This action leverages sensor signals to make more informed decisions about
  HVAC control, using historical data patterns and real-time sensor inputs.
  Uses Jido 1.2.0 Action API with enhanced sensor integration.
  """

  use Jido.Action,
    name: "sensor_data_processor",
    description: "Processes sensor data for intelligent HVAC decision making",
    schema: [
      sensor_signals: [
        type: {:list, :map},
        required: true,
        doc: "List of sensor signals to process"
      ],
      hvac_options: [type: :map, required: true, doc: "HVAC configuration options"],
      state_machine_pid: [type: :pid, required: true, doc: "State machine process ID"],
      decision_window: [
        type: :pos_integer,
        default: 300_000,
        doc: "Time window for decision making in ms"
      ]
    ]

  require Logger

  @impl Jido.Action
  def run(params, _context) do
    Logger.info("Processing #{length(params.sensor_signals)} sensor signals for HVAC decisions")

    with {:ok, processed_data} <- process_sensor_signals(params.sensor_signals),
         {:ok, decision} <- make_hvac_decision(processed_data, params.hvac_options),
         {:ok, _} <- apply_decision(decision, params.state_machine_pid, params.hvac_options) do
      result = %{
        processed_signals: length(params.sensor_signals),
        decision: decision,
        timestamp: DateTime.utc_now(),
        success: true
      }

      Logger.debug("Sensor data processing result: #{inspect(result)}")
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Sensor data processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def compensate(params, _context, _error) do
    Logger.warning("Sensor data processing compensation - reverting to safe mode")

    # Revert to conservative HVAC settings on failure
    HagEx.Hvac.StateMachine.update_conditions(
      params.state_machine_pid,
      # Safe indoor temperature
      21.0,
      # No outdoor temp
      nil,
      DateTime.utc_now().hour,
      Date.day_of_week(DateTime.utc_now()) <= 5
    )

    :ok
  end

  # Helper functions

  defp process_sensor_signals(signals) do
    processed =
      Enum.reduce(signals, %{}, fn signal, acc ->
        case signal do
          %{topic: "hvac.temperature.updated", payload: payload} ->
            Map.merge(acc, %{
              current_temp: payload.current_temperature,
              outdoor_temp: payload.outdoor_temperature,
              temp_delta: payload.delta,
              timestamp: payload.timestamp,
              is_workday: payload.is_workday,
              hour: payload.hour
            })

          _ ->
            acc
        end
      end)

    if Map.has_key?(processed, :current_temp) do
      {:ok, processed}
    else
      {:error, :no_temperature_data}
    end
  end

  defp make_hvac_decision(sensor_data, hvac_options) do
    current_temp = sensor_data.current_temp
    outdoor_temp = sensor_data.outdoor_temp
    hour = sensor_data.hour
    is_workday = sensor_data.is_workday

    # Enhanced decision logic using sensor context
    decision =
      cond do
        # Night time or weekend - use eco settings
        hour < 6 or hour > 22 or not is_workday ->
          make_eco_decision(current_temp, hvac_options)

        # Extreme outdoor conditions - adjust indoor targets
        outdoor_temp && outdoor_temp < -5 ->
          make_cold_weather_decision(current_temp, hvac_options)

        outdoor_temp && outdoor_temp > 35 ->
          make_hot_weather_decision(current_temp, hvac_options)

        # Normal operating conditions
        true ->
          make_standard_decision(current_temp, hvac_options)
      end

    Logger.debug(
      "HVAC decision: #{inspect(decision)} based on temp=#{current_temp}°C, outdoor=#{outdoor_temp}°C, hour=#{hour}"
    )

    {:ok, decision}
  end

  defp make_eco_decision(current_temp, hvac_options) do
    # Lower heating by 1°C
    heating_target = hvac_options.heating.temperature - 1.0
    # Higher cooling by 1°C
    cooling_target = hvac_options.cooling.temperature + 1.0

    cond do
      current_temp < heating_target - 0.5 ->
        %{action: :heat, target: heating_target, mode: :eco}

      current_temp > cooling_target + 0.5 ->
        %{action: :cool, target: cooling_target, mode: :eco}

      true ->
        %{action: :maintain, mode: :eco}
    end
  end

  defp make_cold_weather_decision(current_temp, hvac_options) do
    # More aggressive heating in cold weather
    heating_target = hvac_options.heating.temperature + 0.5

    if current_temp < heating_target do
      %{action: :heat, target: heating_target, mode: :cold_weather}
    else
      %{action: :maintain, mode: :cold_weather}
    end
  end

  defp make_hot_weather_decision(current_temp, hvac_options) do
    # More aggressive cooling in hot weather
    cooling_target = hvac_options.cooling.temperature - 0.5

    if current_temp > cooling_target do
      %{action: :cool, target: cooling_target, mode: :hot_weather}
    else
      %{action: :maintain, mode: :hot_weather}
    end
  end

  defp make_standard_decision(current_temp, hvac_options) do
    heating_target = hvac_options.heating.temperature
    cooling_target = hvac_options.cooling.temperature

    cond do
      current_temp < heating_target - 0.3 ->
        %{action: :heat, target: heating_target, mode: :standard}

      current_temp > cooling_target + 0.3 ->
        %{action: :cool, target: cooling_target, mode: :standard}

      true ->
        %{action: :maintain, mode: :standard}
    end
  end

  defp apply_decision(%{action: :heat} = decision, state_machine_pid, _hvac_options) do
    # Update state machine with heating request
    :ok = Finitomata.transition(state_machine_pid, :start_heating, %{
      target_temperature: decision.target,
      mode: decision.mode
    })
    {:ok, :heating_requested}
  end

  defp apply_decision(%{action: :cool} = decision, state_machine_pid, _hvac_options) do
    # Update state machine with cooling request
    :ok = Finitomata.transition(state_machine_pid, :start_cooling, %{
      target_temperature: decision.target,
      mode: decision.mode
    })
    {:ok, :cooling_requested}
  end

  defp apply_decision(%{action: :maintain}, _state_machine_pid, _hvac_options) do
    # No action needed, maintaining current state
    {:ok, :maintain}
  end
end
