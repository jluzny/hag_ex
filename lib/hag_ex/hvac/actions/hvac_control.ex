defmodule HagEx.Hvac.Actions.HvacControl do
  @moduledoc """
  Jido Action for controlling HVAC entities based on state machine decisions.

  Uses Jido 1.2.0 Action API to create composable HVAC control behavior.
  """

  use Jido.Action,
    name: "hvac_control",
    description: "Controls HVAC entities based on system mode and configuration",
    schema: [
      mode: [type: {:in, [:heat, :cool, :off]}, required: true, doc: "HVAC operation mode"],
      entities: [type: {:list, :map}, required: true, doc: "List of HVAC entities to control"],
      temperature: [type: :float, doc: "Target temperature"],
      preset_mode: [type: :string, doc: "HVAC preset mode"]
    ]

  require Logger
  alias HagEx.HomeAssistant.Client

  @impl Jido.Action
  def run(params, _context) do
    Logger.info("Setting HVAC entities to #{params.mode} mode")

    enabled_entities = Enum.filter(params.entities, & &1.enabled)
    results = Enum.map(enabled_entities, &control_entity(&1, params))

    success_count = Enum.count(results, &(&1 == :ok))
    total_count = length(enabled_entities)

    case success_count do
      ^total_count ->
        {:ok,
         %{
           mode: params.mode,
           entities_controlled: total_count,
           all_successful: true
         }}

      0 ->
        {:error, :all_entities_failed}

      _ ->
        {:ok,
         %{
           mode: params.mode,
           entities_controlled: success_count,
           total_entities: total_count,
           all_successful: false,
           partial_success: true
         }}
    end
  end

  def compensate(params, _context, _error) do
    Logger.warning("HVAC control compensation - attempting to turn off all entities")

    enabled_entities = Enum.filter(params.entities, & &1.enabled)

    Enum.each(enabled_entities, fn entity ->
      Client.call_service("climate", "set_hvac_mode", %{
        "entity_id" => entity.entity_id,
        "hvac_mode" => "off"
      })
    end)

    :ok
  end

  # Helper functions

  defp control_entity(entity, %{mode: :off}) do
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

  defp control_entity(entity, %{mode: mode, temperature: temp, preset_mode: preset})
       when mode in [:heat, :cool] and not is_nil(temp) and not is_nil(preset) do
    mode_str = to_string(mode)

    with {:ok, _} <-
           Client.call_service("climate", "set_hvac_mode", %{
             "entity_id" => entity.entity_id,
             "hvac_mode" => mode_str
           }),
         {:ok, _} <-
           Client.call_service("climate", "set_preset_mode", %{
             "entity_id" => entity.entity_id,
             "preset_mode" => preset
           }),
         {:ok, _} <-
           Client.call_service("climate", "set_temperature", %{
             "entity_id" => entity.entity_id,
             "temperature" => temp
           }) do
      Logger.debug(
        "Successfully configured #{entity.entity_id}: #{mode_str} at #{temp}°C with #{preset}"
      )

      :ok
    else
      {:error, reason} ->
        Logger.error("Failed to configure #{entity.entity_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp control_entity(entity, params) do
    Logger.error("Invalid control parameters for #{entity.entity_id}: #{inspect(params)}")
    {:error, :invalid_parameters}
  end
end
