# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

HAG HVAC Control System (Elixir) is an intelligent HVAC automation system for Home Assistant, implemented using modern Elixir frameworks. This is a migration from the original Rust implementation, demonstrating superior fault tolerance and maintainability through OTP design patterns.

The system uses **Finitomata 0.34.0** for state machine management and **Jido 1.2.0** for autonomous agent-based control.

## Project Structure

This is an Elixir Mix project with the following key components:

### Core Architecture
- **HagEx.Config**: YAML configuration loader with environment variable overrides
- **HagEx.HomeAssistant.Client**: WebSocket client for Home Assistant integration  
- **HagEx.Hvac.StateMachine**: Finitomata 0.34.0 state machine with timer-based evaluation
- **HagEx.Hvac.Agent**: Jido 1.2.0 autonomous agent for intelligent HVAC control
- **HagEx.Hvac.Actions**: Composable Jido actions for temperature monitoring and HVAC control
- **HagEx.Hvac.Controller**: Main controller orchestrating agents and state machines

### File Organization
```
lib/hag_ex/
├── application.ex              # OTP application startup
├── config.ex                  # Configuration management
├── hag_ex.ex                  # Public API module
├── home_assistant/
│   └── client.ex              # WebSocket client for Home Assistant
└── hvac/
    ├── controller.ex          # Main HVAC orchestration
    ├── state_machine.ex       # Finitomata FSM (latest API)
    ├── agent.ex              # Jido autonomous agent
    └── actions/
        ├── temperature_monitor.ex  # Temperature monitoring action
        └── hvac_control.ex        # HVAC control action

config/
├── config.exs                 # Base configuration
├── dev.exs                   # Development config
├── test.exs                  # Test config
├── prod.exs                  # Production config
├── hvac_config.yaml          # Main HVAC configuration
├── hvac_config_dev.yaml      # Development HVAC config
└── hvac_config_test.yaml     # Test HVAC config

test/
└── hag_ex/
    └── config_test.exs        # Configuration tests
```

## Common Commands

### Development
```bash
mix deps.get                   # Install dependencies
mix compile                    # Compile project
mix test                      # Run tests
iex -S mix                    # Interactive shell
mix run --no-halt             # Run application
```

### Code Quality
```bash
mix credo                     # Static analysis
mix dialyzer                  # Type checking (runs automatically after compile)
mix check                     # Run all code quality checks
mix docs                      # Generate documentation
mix format                    # Format code
```

### Configuration
- Production config: `config/hvac_config.yaml`
- Development config: `config/hvac_config_dev.yaml`  
- Test config: `config/hvac_config_test.yaml`
- Environment variables: `HASS_TOKEN` for Home Assistant authentication

## Framework-Specific Guidelines

### Finitomata 0.34.0 State Machine

**Modern State Definition (DO USE):**
```elixir
@fsm """
[*] --> idle
idle --> |start_heating| heating
idle --> |start_cooling| cooling
heating --> |stop_heating| idle
"""

use Finitomata, 
  fsm: @fsm, 
  syntax: :state_diagram,
  timer: 5000,
  auto_terminate: false
```

**Transition Callbacks (CORRECT API):**
```elixir
@impl Finitomata
def on_transition(from_state, event, event_payload, state_payload) do
  # 4-parameter API is correct for v0.34.0
  {:ok, new_state, updated_state_payload}
end

@impl Finitomata
def on_timer(state_payload) do
  # Timer callback for periodic evaluation
  {:ok, state_payload}
end
```

**DO NOT use old API:**
```elixir
# OLD - Don't use this
def on_transition(from_state, to_state, payload) # 3-parameter API is outdated
```

### Jido 1.2.0 Agents and Actions

**Action Definition (CORRECT):**
```elixir
defmodule MyApp.Actions.SomeAction do
  use Jido.Action,
    name: "action_name",
    description: "What this action does",
    schema: [
      param1: [type: :string, required: true, doc: "Description"],
      param2: [type: :integer, default: 100, doc: "Description"]
    ]

  @impl Jido.Action
  def run(params, context) do
    # Action logic here
    {:ok, result}
  end

  @impl Jido.Action  
  def compensate(params, context, error) do
    # Error compensation logic
    :ok
  end
end
```

**Agent Definition (CORRECT):**
```elixir
defmodule MyApp.Agent do
  use Jido.Agent,
    name: "agent_name",
    description: "Agent description",
    actions: [MyApp.Actions.Action1, MyApp.Actions.Action2],
    schema: [
      config_param: [type: :map, required: true]
    ]

  @impl Jido.Agent
  def mount(state) do
    # Agent initialization
    {:ok, state}
  end
end
```

## Configuration Management

### YAML Structure
The system uses centralized HVAC configuration:

```yaml
hass_options:
  ws_url: "ws://your-ha:8123/api/websocket"
  rest_url: "http://your-ha:8123"
  token: "override_with_env_HASS_TOKEN"

hvac_options:
  temp_sensor: "sensor.temperature"
  system_mode: "auto"  # auto, heat_only, cool_only, off
  
  hvac_entities:
    - entity_id: "climate.ac"
      enabled: true
      defrost: true

  heating:
    temperature: 21.0
    preset_mode: "windFreeSleep"
    temperature_thresholds:
      indoor_min: 19.7
      indoor_max: 20.2
      outdoor_min: -10.0
      outdoor_max: 15.0

  cooling:
    temperature: 24.0
    preset_mode: "windFree"
    temperature_thresholds:
      indoor_min: 23.0
      indoor_max: 23.5
      outdoor_min: 10.0
      outdoor_max: 45.0
```

### Environment Variables
- `HASS_TOKEN`: Home Assistant long-lived access token (required)
- `MIX_ENV`: Environment (dev/test/prod)

## Testing Guidelines

### Configuration Tests
Test configuration parsing and validation:
```elixir
test "parses HVAC configuration correctly" do
  {:ok, config} = HagEx.Config.load("config/hvac_config_test.yaml")
  assert config.hvac_options.temp_sensor == "sensor.test"
end
```

### Action Tests
Test Jido actions independently:
```elixir
test "temperature monitor action" do
  params = %{temp_sensor: "sensor.test", state_machine_pid: self()}
  {:ok, result} = HagEx.Hvac.Actions.TemperatureMonitor.run(params, %{})
  assert result.conditions_updated == true
end
```

### State Machine Tests
Test Finitomata state transitions:
```elixir
test "heating transition" do
  {:ok, pid} = HagEx.Hvac.StateMachine.start_link(hvac_options)
  :ok = Finitomata.transition(pid, :start_heating, %{})
  {:ok, {state, _}} = Finitomata.state(pid)
  assert state == :heating
end
```

## Error Handling

### Framework-Specific Error Patterns

**Finitomata Errors:**
- State machine validation errors occur at compile time
- Transition failures return `{:error, reason}` 
- Use `on_failure/3` callback for error handling

**Jido Action Errors:**
- Actions should return `{:ok, result}` or `{:error, reason}`
- Implement `compensate/3` for error recovery
- Agents automatically handle action failures

**Home Assistant Client Errors:**
- WebSocket disconnections trigger automatic reconnection
- Service call failures should be logged and retried
- Authentication errors require token validation

## Development Notes

### Adding New HVAC Logic
1. Create new Jido Action in `lib/hag_ex/hvac/actions/`
2. Add action to agent's action list
3. Implement with proper schema validation
4. Add compensation logic for error handling
5. Write unit tests for the action

### Modifying State Machine
1. Update PlantUML state diagram in `@fsm` module attribute
2. Implement corresponding `on_transition/4` callbacks
3. Update `determine_target_event/1` logic if needed
4. Test state transitions thoroughly

### Configuration Changes
1. Update YAML config files (prod, dev, test)
2. Update `HagEx.Config` parsing if needed
3. Update schema validation in actions/agents
4. Test configuration loading

## Dependencies

### Core Dependencies
- `finitomata ~> 0.34.0`: State machine framework (latest)
- `jido ~> 1.2.0`: Agent and workflow framework (latest)
- `yaml_elixir ~> 2.9`: YAML configuration parsing
- `jason ~> 1.4`: JSON serialization
- `websockex ~> 0.4`: WebSocket client for Home Assistant
- `req ~> 0.4`: HTTP client

### Development Dependencies  
- `ex_doc ~> 0.31`: Documentation generation
- `credo ~> 1.7`: Static analysis
- `dialyxir ~> 1.4`: Type checking

## Important Reminders

### Framework Versions
- **ALWAYS use Finitomata 0.34.0** - This project uses the latest API
- **ALWAYS use Jido 1.2.0** - This project uses the latest agent system
- **DO NOT** downgrade to older versions or use outdated API patterns

### Code Patterns
- Use timer-based evaluation in Finitomata (5-second intervals)
- Implement compensation logic in all Jido actions
- Always handle Home Assistant connection failures gracefully
- Use schema validation for all user inputs
- Follow OTP supervision tree principles

### Configuration
- Environment variables override YAML settings
- Test configurations should mirror production structure
- Always validate configuration on startup
- Use meaningful error messages for configuration failures

### Git Commit Guidelines
- **NEVER mention Claude, AI, or automated generation** in commit messages
- Focus on what was implemented and why
- Use conventional commit format when appropriate
- Keep messages concise and technical

## Architecture Decisions

### Why Finitomata 0.34.0?
- Built-in timer support eliminates external scheduling
- PlantUML syntax provides clear state visualization
- Enhanced error handling and state recovery
- Better integration with OTP supervision trees

### Why Jido 1.2.0?
- Autonomous agent behavior reduces manual orchestration
- Composable actions improve testability and reusability  
- Built-in compensation provides automatic error recovery
- Schema validation ensures robust parameter handling

### Why This Architecture?
- **Separation of Concerns**: State machine handles states, agent handles decisions
- **Fault Tolerance**: Multiple supervision levels (OTP + Agent + State machine)
- **Maintainability**: Declarative state definitions and composable actions
- **Observability**: Built-in logging, monitoring, and health checks

## Related Projects

- [Original Rust HAG](../hag) - Source implementation this migrates from
- [Finitomata Documentation](https://hexdocs.pm/finitomata/0.34.0/)
- [Jido Documentation](https://hexdocs.pm/jido/1.2.0/)