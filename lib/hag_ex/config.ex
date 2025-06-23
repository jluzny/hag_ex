defmodule HagEx.Config do
  @moduledoc """
  Configuration loader for HVAC system settings.

  Loads configuration from YAML files and environment variables,
  providing structured access to HVAC and Home Assistant settings.
  """

  defstruct [
    :hass_options,
    :hvac_options
  ]

  @type t :: %__MODULE__{
          hass_options: HassOptions.t(),
          hvac_options: HvacOptions.t()
        }

  defmodule HassOptions do
    @moduledoc "Home Assistant connection options"

    defstruct [
      :ws_url,
      :rest_url,
      :token,
      :max_retries,
      :retry_delay_ms,
      :state_check_interval
    ]

    @type t :: %__MODULE__{
            ws_url: String.t(),
            rest_url: String.t(),
            token: String.t(),
            max_retries: pos_integer(),
            retry_delay_ms: pos_integer(),
            state_check_interval: pos_integer()
          }
  end

  defmodule HvacOptions do
    @moduledoc "HVAC system configuration"

    defstruct [
      :temp_sensor,
      :system_mode,
      :hvac_entities,
      :heating,
      :cooling,
      :active_hours
    ]

    @type system_mode :: :heat_only | :cool_only | :auto | :off
    @type t :: %__MODULE__{
            temp_sensor: String.t(),
            system_mode: system_mode(),
            hvac_entities: [HvacEntity.t()],
            heating: HeatingOptions.t(),
            cooling: CoolingOptions.t(),
            active_hours: ActiveHours.t()
          }
  end

  defmodule HvacEntity do
    @moduledoc "Individual HVAC entity configuration"

    defstruct [:entity_id, :enabled, :defrost]

    @type t :: %__MODULE__{
            entity_id: String.t(),
            enabled: boolean(),
            defrost: boolean()
          }
  end

  defmodule TemperatureThresholds do
    @moduledoc "Temperature thresholds for heating/cooling activation"

    defstruct [:indoor_min, :indoor_max, :outdoor_min, :outdoor_max]

    @type t :: %__MODULE__{
            indoor_min: float(),
            indoor_max: float(),
            outdoor_min: float(),
            outdoor_max: float()
          }
  end

  defmodule HeatingOptions do
    @moduledoc "Heating-specific configuration"

    defstruct [:temperature, :preset_mode, :temperature_thresholds, :defrost]

    @type t :: %__MODULE__{
            temperature: float(),
            preset_mode: String.t(),
            temperature_thresholds: TemperatureThresholds.t(),
            defrost: DefrostOptions.t()
          }
  end

  defmodule CoolingOptions do
    @moduledoc "Cooling-specific configuration"

    defstruct [:temperature, :preset_mode, :temperature_thresholds]

    @type t :: %__MODULE__{
            temperature: float(),
            preset_mode: String.t(),
            temperature_thresholds: TemperatureThresholds.t()
          }
  end

  defmodule DefrostOptions do
    @moduledoc "Defrost cycle configuration"

    defstruct [:temperature_threshold, :period_seconds, :duration_seconds]

    @type t :: %__MODULE__{
            temperature_threshold: float(),
            period_seconds: pos_integer(),
            duration_seconds: pos_integer()
          }
  end

  defmodule ActiveHours do
    @moduledoc "Active hours configuration"

    defstruct [:start, :start_weekday, :end]

    @type t :: %__MODULE__{
            start: 0..23,
            start_weekday: 0..23,
            end: 0..23
          }
  end

  @doc """
  Load configuration from YAML file with environment variable overrides.

  ## Examples

      iex> HagEx.Config.load("config/hvac_config.yaml")
      {:ok, %HagEx.Config{...}}
  """
  @spec load(String.t()) :: {:ok, t()} | {:error, term()}
  def load(config_file) do
    with {:ok, raw_config} <- YamlElixir.read_from_file(config_file),
         {:ok, config} <- parse_config(raw_config) do
      {:ok, apply_env_overrides(config)}
    end
  end

  @spec parse_config(map()) :: {:ok, t()} | {:error, term()}
  def parse_config(raw_config) do
    try do
      config = %__MODULE__{
        hass_options: parse_hass_options(raw_config["hass_options"]),
        hvac_options: parse_hvac_options(raw_config["hvac_options"])
      }

      {:ok, config}
    rescue
      error -> {:error, error}
    end
  end

  defp parse_hass_options(nil), do: %HassOptions{}

  defp parse_hass_options(opts) do
    %HassOptions{
      ws_url: opts["ws_url"],
      rest_url: opts["rest_url"],
      token: opts["token"],
      max_retries: opts["max_retries"] || 5,
      retry_delay_ms: opts["retry_delay_ms"] || 1000,
      state_check_interval: opts["state_check_interval"] || 600_000
    }
  end

  defp parse_hvac_options(nil), do: %HvacOptions{}

  defp parse_hvac_options(opts) do
    %HvacOptions{
      temp_sensor: opts["temp_sensor"],
      system_mode: parse_system_mode(opts["system_mode"]),
      hvac_entities: parse_hvac_entities(opts["hvac_entities"] || []),
      heating: parse_heating_options(opts["heating"]),
      cooling: parse_cooling_options(opts["cooling"]),
      active_hours: parse_active_hours(opts["active_hours"])
    }
  end

  defp parse_system_mode("heat_only"), do: :heat_only
  defp parse_system_mode("cool_only"), do: :cool_only
  defp parse_system_mode("auto"), do: :auto
  defp parse_system_mode("off"), do: :off
  defp parse_system_mode(_), do: :auto

  defp parse_hvac_entities(entities) do
    Enum.map(entities, fn entity ->
      %HvacEntity{
        entity_id: entity["entity_id"],
        enabled: entity["enabled"] || false,
        defrost: entity["defrost"] || false
      }
    end)
  end

  defp parse_heating_options(nil), do: %HeatingOptions{}

  defp parse_heating_options(opts) do
    %HeatingOptions{
      temperature: opts["temperature"],
      preset_mode: opts["preset_mode"],
      temperature_thresholds: parse_temperature_thresholds(opts["temperature_thresholds"]),
      defrost: parse_defrost_options(opts["defrost"])
    }
  end

  defp parse_cooling_options(nil), do: %CoolingOptions{}

  defp parse_cooling_options(opts) do
    %CoolingOptions{
      temperature: opts["temperature"],
      preset_mode: opts["preset_mode"],
      temperature_thresholds: parse_temperature_thresholds(opts["temperature_thresholds"])
    }
  end

  defp parse_temperature_thresholds(nil), do: %TemperatureThresholds{}

  defp parse_temperature_thresholds(thresholds) do
    %TemperatureThresholds{
      indoor_min: thresholds["indoor_min"],
      indoor_max: thresholds["indoor_max"],
      outdoor_min: thresholds["outdoor_min"],
      outdoor_max: thresholds["outdoor_max"]
    }
  end

  defp parse_defrost_options(nil), do: %DefrostOptions{}

  defp parse_defrost_options(opts) do
    %DefrostOptions{
      temperature_threshold: opts["temperature_threshold"],
      period_seconds: opts["period_seconds"],
      duration_seconds: opts["duration_seconds"]
    }
  end

  defp parse_active_hours(nil), do: %ActiveHours{}

  defp parse_active_hours(opts) do
    %ActiveHours{
      start: opts["start"],
      start_weekday: opts["start_weekday"],
      end: opts["end"]
    }
  end

  defp apply_env_overrides(%__MODULE__{hass_options: hass_opts} = config) do
    # Apply environment variable overrides for sensitive data
    updated_hass_opts = %{hass_opts | token: System.get_env("HASS_TOKEN", hass_opts.token)}

    %{config | hass_options: updated_hass_opts}
  end
end
