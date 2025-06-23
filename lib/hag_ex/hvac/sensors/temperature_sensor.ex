defmodule HagEx.Hvac.Sensors.TemperatureSensor do
  @moduledoc """
  Jido Sensor for monitoring Home Assistant temperature entities.

  This sensor continuously monitors temperature readings from Home Assistant
  and emits signals when temperature changes occur or thresholds are met.
  Uses Jido 1.2.0 Sensor API for reliable data collection and signal emission.
  """

  use Jido.Sensor,
    name: "temperature_sensor",
    description:
      "Monitors Home Assistant temperature entities and emits temperature change signals",
    category: :monitoring,
    tags: [:hvac, :temperature, :home_assistant],
    vsn: "1.0.0",
    schema: [
      entity_id: [type: :string, required: true, doc: "Temperature sensor entity ID"],
      poll_interval: [
        type: :pos_integer,
        default: 30_000,
        doc: "Polling interval in milliseconds"
      ],
      threshold_delta: [
        type: :float,
        default: 0.5,
        doc: "Temperature change threshold for signal emission"
      ],
      outdoor_sensor: [type: :string, doc: "Optional outdoor temperature sensor for context"]
    ]

  require Logger
  alias HagEx.HomeAssistant.Client

  @impl Jido.Sensor
  def mount(config) do
    Logger.info("Temperature sensor mounting for entity: #{config.entity_id}")

    # Initialize with current temperature reading
    case get_temperature(config.entity_id) do
      {:ok, temp} ->
        enhanced_state =
          Map.merge(config, %{
            last_temperature: temp,
            last_outdoor_temp: get_optional_outdoor_temp(config),
            last_reading_time: DateTime.utc_now()
          })

        # Schedule first poll
        schedule_next_poll(config.poll_interval)

        {:ok, enhanced_state}

      {:error, reason} ->
        Logger.error("Failed to initialize temperature sensor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Jido.Sensor
  def deliver_signal(state) do
    case get_temperature(state.entity_id) do
      {:ok, current_temp} ->
        outdoor_temp = get_optional_outdoor_temp(state)
        now = DateTime.utc_now()

        # Check if temperature change is significant enough to emit signal
        should_emit =
          should_emit_signal?(current_temp, state.last_temperature, state.threshold_delta)

        if should_emit do
          {:ok, signal} =
            Jido.Signal.new(%{
              type: "hvac.temperature.updated",
              source: "/hvac/sensors/temperature",
              data: %{
                entity_id: state.entity_id,
                current_temperature: current_temp,
                previous_temperature: state.last_temperature,
                outdoor_temperature: outdoor_temp,
                delta: current_temp - (state.last_temperature || current_temp),
                timestamp: DateTime.to_iso8601(now),
                is_workday: Date.day_of_week(now) <= 5,
                hour: now.hour
              }
            })

          Logger.debug(
            "Temperature sensor emitting signal: #{current_temp}°C (delta: #{current_temp - (state.last_temperature || current_temp)})"
          )

          {:ok, signal}
        else
          # No signal to emit
          {:ok, nil}
        end

      {:error, reason} ->
        Logger.warning("Temperature sensor failed to read: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl Jido.Sensor
  def on_before_deliver(signal, state) do
    # Add additional context to signal before delivery
    enhanced_data =
      Map.merge(signal.data, %{
        sensor_id: state.id || "unknown",
        config: %{
          poll_interval: state.poll_interval,
          threshold_delta: state.threshold_delta
        }
      })

    enhanced_signal = %{signal | data: enhanced_data}
    {:ok, enhanced_signal}
  end

  @impl Jido.Sensor
  def shutdown(state) do
    Logger.info("Temperature sensor shutting down for entity: #{state.entity_id}")
    {:ok, state}
  end

  # GenServer callbacks for polling

  @impl GenServer
  def handle_info(:poll_temperature, state) do
    # Trigger signal delivery check
    case deliver_signal(state) do
      {:ok, signal} when not is_nil(signal) ->
        # Update state with new readings from signal data
        updated_state = %{
          state
          | last_temperature: signal.data.current_temperature,
            last_outdoor_temp: signal.data.outdoor_temperature,
            last_reading_time: DateTime.utc_now()
        }

        # Sensor framework will handle signal dispatch
        schedule_next_poll(state.poll_interval)
        {:noreply, updated_state}

      {:ok, nil} ->
        # No signal emitted, update state directly
        {:ok, current_temp} = get_temperature(state.entity_id)

        updated_state = %{
          state
          | last_temperature: current_temp,
            last_outdoor_temp: get_optional_outdoor_temp(state),
            last_reading_time: DateTime.utc_now()
        }

        schedule_next_poll(state.poll_interval)
        {:noreply, updated_state}

      {:error, reason} ->
        Logger.warning("Temperature polling failed: #{inspect(reason)}")
        schedule_next_poll(state.poll_interval)
        {:noreply, state}
    end
  end

  # Helper functions

  defp get_temperature(entity_id) do
    case Client.get_state(entity_id) do
      {:ok, %{"state" => temp_str}} when is_binary(temp_str) ->
        case Float.parse(temp_str) do
          {temp, ""} -> {:ok, temp}
          _ -> {:error, {:invalid_temperature_format, temp_str}}
        end

      {:ok, nil} ->
        {:error, {:sensor_not_found, entity_id}}

      {:error, reason} ->
        {:error, {:client_error, reason}}
    end
  end

  defp get_optional_outdoor_temp(%{outdoor_sensor: outdoor_sensor})
       when not is_nil(outdoor_sensor) do
    case get_temperature(outdoor_sensor) do
      {:ok, temp} -> temp
      {:error, _} -> nil
    end
  end

  defp get_optional_outdoor_temp(_config), do: nil

  defp should_emit_signal?(_current_temp, nil, _threshold), do: true

  defp should_emit_signal?(current_temp, last_temp, threshold) do
    abs(current_temp - last_temp) >= threshold
  end

  defp schedule_next_poll(interval_ms) do
    Process.send_after(self(), :poll_temperature, interval_ms)
  end
end
