defmodule HagEx.Hvac.Actions.SensorDataProcessor do
  @moduledoc """
  Jido Action for processing sensor data and updating the state machine.
  """

  use Jido.Action,
    name: "sensor_data_processor",
    description: "Processes sensor signals and updates the HVAC state machine",
    schema: [
      sensor_signals: [type: {:list, :map}, required: true, doc: "List of sensor signals"],
      hvac_options: [type: :map, required: true, doc: "HVAC configuration options"],
      state_machine_pid: [type: :pid, required: true, doc: "HVAC state machine process ID"],
      decision_window: [type: :pos_integer, default: 300_000, doc: "Decision window in milliseconds"]
    ]

  require Logger
  alias HagEx.Hvac.StateMachine

  @impl Jido.Action
  def run(params, _context) do
    Logger.debug("Processing sensor data: #{inspect(params.sensor_signals)}")

    # Extract relevant data from sensor_signals
    # For now, assuming a single temperature update signal
    case Enum.find(params.sensor_signals, fn signal ->
           Map.get(signal, :topic) == "hvac.temperature.updated"
         end) do
      nil ->
        Logger.warning("No 'hvac.temperature.updated' signal found in sensor_signals.")
        {:ok, %{conditions_updated: false, reason: :no_temperature_signal}}

      %{payload: payload} ->
        # Assuming payload contains current_temperature, outdoor_temperature, hour, is_workday
        # This needs to align with what TemperatureMonitor action produces
        current_temperature = Map.get(payload, :temperature)
        outdoor_temperature = Map.get(payload, :outdoor_temperature)
        hour = Map.get(payload, :hour)
        is_workday = Map.get(payload, :is_weekday) # Renamed from is_workday to is_weekday for consistency

        if current_temperature && outdoor_temperature && hour && is_workday do
          StateMachine.update_conditions(
            params.state_machine_pid,
            current_temperature,
            outdoor_temperature,
            hour,
            is_workday
          )

          {:ok, %{conditions_updated: true, indoor_temp: current_temperature, outdoor_temp: outdoor_temperature}}
        else
          Logger.error("Missing required sensor data in payload: #{inspect(payload)}")
          {:error, :missing_sensor_data}
        end
    end
  end

  @impl Jido.Action
  def on_error(params, _context, error, _opts) do
    Logger.warning("Sensor data processing error: #{inspect(error)}. Params: #{inspect(params)}")
    # No specific compensation needed for this action, just log
    :ok
  end
end