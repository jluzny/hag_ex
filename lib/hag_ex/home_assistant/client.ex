defmodule HagEx.HomeAssistant.Client do
  @moduledoc """
  WebSocket client for Home Assistant integration.

  Handles authentication, event subscription, and service calls
  to Home Assistant via WebSocket API.
  """

  use WebSockex
  require Logger

  alias HagEx.Config.HassOptions

  defstruct [
    :hass_options,
    :auth_id,
    :subscription_id,
    :message_id,
    :subscribers
  ]

  @type t :: %__MODULE__{
          hass_options: HassOptions.t(),
          auth_id: pos_integer() | nil,
          subscription_id: pos_integer() | nil,
          message_id: pos_integer(),
          subscribers: [pid()]
        }

  # Client API

  @doc """
  Start the Home Assistant WebSocket client.
  """
  @spec start_link(HassOptions.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(%HassOptions{} = hass_options) do
    Logger.info("🔌 Starting Home Assistant WebSocket client")
    Logger.debug("🏠 Connecting to: #{hass_options.ws_url}")
    Logger.debug("🔑 Token configured: #{String.length(hass_options.token)} chars")

    Logger.debug(
      "🔄 Max retries: #{hass_options.max_retries}, delay: #{hass_options.retry_delay_ms}ms"
    )

    state = %__MODULE__{
      hass_options: hass_options,
      message_id: 1,
      subscribers: []
    }

    Logger.debug("📡 Attempting WebSocket connection...")

    case WebSockex.start_link(hass_options.ws_url, __MODULE__, state, name: __MODULE__) do
      {:ok, pid} ->
        Logger.debug("✅ WebSocket client started with PID: #{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("❌ Failed to start WebSocket client: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Subscribe to Home Assistant state change events.
  """
  @spec subscribe_events() :: :ok
  @spec subscribe_events(pid() | atom()) :: :ok
  def subscribe_events(client_pid \\ __MODULE__) do
    WebSockex.cast(client_pid, {:subscribe_events, self()})
    :ok
  end

  @doc """
  Get current state of an entity.
  """
  @spec get_state(String.t()) :: {:ok, map() | nil} | {:error, term()}
  @spec get_state(String.t(), pid() | atom()) :: {:ok, map() | nil} | {:error, term()}
  def get_state(entity_id, client_pid \\ __MODULE__) do
    send(client_pid, {:get_state_request, entity_id, self()})

    receive do
      {:get_state_response, result} -> result
    after
      5000 -> {:error, :timeout}
    end
  end

  @doc """
  Call a Home Assistant service.
  """
  @spec call_service(String.t(), String.t(), map()) :: {:ok, map() | nil} | {:error, term()}
  @spec call_service(String.t(), String.t(), map(), pid() | atom()) ::
          {:ok, map() | nil} | {:error, term()}
  def call_service(domain, service, service_data, client_pid \\ __MODULE__) do
    send(client_pid, {:call_service_request, domain, service, service_data, self()})

    receive do
      {:call_service_response, result} -> result
    after
      5000 -> {:error, :timeout}
    end
  end

  # WebSockex callbacks

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("🔗 Connected to Home Assistant WebSocket")
    Logger.debug("📡 WebSocket connection established")
    {:ok, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    Logger.debug(
      "📨 Received WebSocket message: #{String.slice(msg, 0, 200)}#{if String.length(msg) > 200, do: "...", else: ""}"
    )

    case Jason.decode(msg) do
      {:ok, %{"type" => "auth_required"}} ->
        Logger.debug("🔐 Authentication required - sending token...")
        authenticate(state)

      {:ok, %{"type" => "auth_ok"}} ->
        Logger.info("✅ Home Assistant authentication successful")
        Logger.debug("📝 Subscribing to state change events...")
        subscribe_to_events(state)

      {:ok, %{"type" => "auth_invalid", "message" => message}} ->
        Logger.error("❌ Home Assistant authentication failed: #{message}")
        {:close, state}

      {:ok, %{"type" => "event", "event" => event}} ->
        Logger.debug(
          "📡 Received event: #{event["event_type"]} for #{event["data"]["entity_id"] || "unknown"}"
        )

        handle_event(event, state)

      {:ok, %{"type" => "result", "success" => true, "id" => id, "result" => result}} ->
        Logger.debug("✅ Result success for ID #{id}: #{inspect(result)}")
        handle_result_success(id, result, state)

      {:ok, %{"type" => "result", "success" => false, "id" => id, "error" => error}} ->
        Logger.warning("⚠️  Result error for ID #{id}: #{inspect(error)}")
        handle_result_error(id, error, state)

      {:ok, message} ->
        Logger.debug("📬 Unknown message type: #{inspect(message)}")
        {:ok, state}

      {:error, error} ->
        Logger.error("❌ Failed to decode WebSocket message: #{inspect(error)}")
        Logger.debug("Raw message: #{msg}")
        {:ok, state}
    end
  end

  @impl WebSockex
  def handle_cast({:subscribe_events, subscriber_pid}, state) do
    updated_state = %{state | subscribers: [subscriber_pid | state.subscribers]}
    {:ok, updated_state}
  end

  @impl WebSockex
  def handle_info({:get_state_request, entity_id, from_pid}, state) do
    message = %{
      "id" => state.message_id,
      "type" => "get_states"
    }

    # Store the caller for response handling
    Process.put({:call, state.message_id}, {from_pid, :get_state, entity_id})

    updated_state = %{state | message_id: state.message_id + 1}
    {:reply, {:text, Jason.encode!(message)}, updated_state}
  end

  @impl WebSockex
  def handle_info({:call_service_request, domain, service, service_data, from_pid}, state) do
    message = %{
      "id" => state.message_id,
      "type" => "call_service",
      "domain" => domain,
      "service" => service,
      "service_data" => service_data
    }

    # Store the caller for response handling
    Process.put({:call, state.message_id}, {from_pid, :call_service, {domain, service}})

    updated_state = %{state | message_id: state.message_id + 1}
    {:reply, {:text, Jason.encode!(message)}, updated_state}
  end

  @impl WebSockex
  def handle_disconnect(%{reason: reason}, state) do
    Logger.warning("Disconnected from Home Assistant: #{inspect(reason)}")
    {:reconnect, state}
  end

  # Private helper functions

  defp authenticate(state) do
    Logger.debug("🔑 Sending authentication token to Home Assistant")

    auth_message = %{
      "type" => "auth",
      "access_token" => state.hass_options.token
    }

    {:reply, {:text, Jason.encode!(auth_message)}, state}
  end

  defp subscribe_to_events(state) do
    Logger.debug("📡 Subscribing to state_changed events with ID #{state.message_id}")

    subscription_message = %{
      "id" => state.message_id,
      "type" => "subscribe_events",
      "event_type" => "state_changed"
    }

    updated_state = %{state | subscription_id: state.message_id, message_id: state.message_id + 1}

    {:reply, {:text, Jason.encode!(subscription_message)}, updated_state}
  end

  defp handle_event(%{"event_type" => "state_changed"} = event, state) do
    entity_id = get_in(event, ["data", "entity_id"])
    new_state = get_in(event, ["data", "new_state", "state"])
    old_state = get_in(event, ["data", "old_state", "state"])

    Logger.debug("🏠 State changed: #{entity_id} #{old_state} → #{new_state}")
    Logger.debug("📡 Broadcasting to #{length(state.subscribers)} subscribers")

    # Broadcast state change events to subscribers
    Enum.each(state.subscribers, fn subscriber ->
      send(subscriber, {:state_changed, event})
    end)

    {:ok, state}
  end

  defp handle_event(event, state) do
    Logger.debug("Received unhandled event: #{inspect(event)}")
    {:ok, state}
  end

  defp handle_result_success(id, result, state) do
    case Process.get({:call, id}) do
      {from, :get_state, entity_id} ->
        # Find the specific entity state
        entity_state =
          Enum.find(result, fn entity ->
            entity["entity_id"] == entity_id
          end)

        send(from, {:get_state_response, {:ok, entity_state}})
        Process.delete({:call, id})

      {from, :call_service, _service_info} ->
        send(from, {:call_service_response, {:ok, result}})
        Process.delete({:call, id})

      nil ->
        Logger.debug("Received result for unknown call ID: #{id}")
    end

    {:ok, state}
  end

  defp handle_result_error(id, error, state) do
    case Process.get({:call, id}) do
      {from, _call_type, _call_data} ->
        send(from, {:call_service_response, {:error, error}})
        Process.delete({:call, id})

      nil ->
        Logger.error("Received error for unknown call ID #{id}: #{inspect(error)}")
    end

    {:ok, state}
  end
end
