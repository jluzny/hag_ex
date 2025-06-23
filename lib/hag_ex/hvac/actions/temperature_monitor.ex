defmodule HagEx.Hvac.Actions.TemperatureMonitor do
  @moduledoc """
  Jido Action for monitoring temperature sensors and triggering state evaluations.

  Uses Jido 1.2.0 Action API to create composable temperature monitoring behavior.
  """

  use Jido.Action,
    name: "temperature_monitor",
    description:
      "Monitors temperature sensors and evaluates HVAC conditions with sensor integration",
    schema: [
      temp_sensor: [type: :string, required: true, doc: "Temperature sensor entity ID"],
      outdoor_sensor: [
        type: :string,
        default: "sensor.openweathermap_temperature",
        doc: "Outdoor temperature sensor"
      ],
      state_machine_pid: [type: :pid, required: true, doc: "HVAC state machine process ID"],
      check_interval: [
        type: :pos_integer,
        default: 300_000,
        doc: "Check interval in milliseconds"
      ],
      use_sensor_data: [
        type: :boolean,
        default: true,
        doc: "Use sensor signals instead of direct polling"
      ]
    ]

  require Logger
  alias HagEx.HomeAssistant.Client
  alias HagEx.Hvac.StateMachine

  @impl Jido.Action
  def run(params, context) do
    Logger.info("Starting temperature monitoring for #{params.temp_sensor}")

    if params.use_sensor_data do
      # Use sensor data if available in context
      case get_sensor_data_from_context(context) do
        {:ok, sensor_data} ->
          process_sensor_based_monitoring(sensor_data, params)

        {:error, :no_sensor_data} ->
          # Fallback to direct polling
          process_direct_monitoring(params)
      end
    else
      process_direct_monitoring(params)
    end
  end

  def compensate(_params, _context, _error) do
    Logger.warning("Temperature monitoring compensation - will retry on next cycle")
    :ok
  end

  # Helper functions

  defp get_sensor_data_from_context(context) do
    # Extract sensor data from Jido context if available
    case Map.get(context, :sensor_signals) do
      nil ->
        {:error, :no_sensor_data}

      [] ->
        {:error, :no_sensor_data}

      signals ->
        temp_signal =
          Enum.find(signals, fn signal ->
            Map.get(signal, :topic) == "hvac.temperature.updated"
          end)

        if temp_signal do
          {:ok, temp_signal.payload}
        else
          {:error, :no_temperature_signal}
        end
    end
  end

  defp process_sensor_based_monitoring(sensor_data, params) do
    Logger.debug("Using sensor data for monitoring: #{inspect(sensor_data)}")

    # Update state machine with sensor data
    StateMachine.update_conditions(
      params.state_machine_pid,
      sensor_data.current_temperature,
      sensor_data.outdoor_temperature,
      sensor_data.hour,
      sensor_data.is_workday
    )

    result = %{
      indoor_temp: sensor_data.current_temperature,
      outdoor_temp: sensor_data.outdoor_temperature,
      timestamp: sensor_data.timestamp,
      conditions_updated: true,
      data_source: :sensor
    }

    Logger.debug("Sensor-based temperature monitoring result: #{inspect(result)}")
    {:ok, result}
  end

  @spec process_direct_monitoring(map()) :: {:ok, map()} | {:error, term()}
  defp process_direct_monitoring(params) do
    Logger.debug("Using direct polling for monitoring")

    with {:ok, indoor_temp} <- get_temperature(params.temp_sensor),
         {:ok, outdoor_temp} <- get_temperature(params.outdoor_sensor) do
      now = DateTime.utc_now()

      # Update state machine with new conditions
      :ok = StateMachine.update_conditions(
        params.state_machine_pid,
        indoor_temp,
        outdoor_temp,
        now.hour,
        Date.day_of_week(now) <= 5
      )

      result = %{
        indoor_temp: indoor_temp,
        outdoor_temp: outdoor_temp,
        timestamp: now,
        conditions_updated: true,
        data_source: :direct_poll
      }

      Logger.debug("Direct polling temperature monitoring result: #{inspect(result)}")
      {:ok, result}
    else
      {:error, reason} ->
        Logger.error("Temperature monitoring failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec get_temperature(String.t()) :: {:ok, float()} | {:error, term()}
  defp get_temperature(sensor_entity) do
    case Client.get_state(sensor_entity) do
      {:ok, %{"state" => temp_str}} when is_binary(temp_str) ->
        case Float.parse(temp_str) do
          {temp, ""} -> {:ok, temp}
          _ -> {:error, {:invalid_temperature_format, temp_str}}
        end

      {:ok, nil} ->
        {:error, {:sensor_not_found, sensor_entity}}

      {:error, reason} ->
        {:error, {:client_error, reason}}
    end
  end
end
