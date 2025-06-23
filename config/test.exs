import Config

# Configure logger for test with console backend
config :logger,
  level: :debug,
  backends: [:console]

# Configure console backend specifically for tests
config :logger, :console,
  level: :debug,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Test specific configuration - don't start application automatically
config :hag_ex,
  config_file: "config/hvac_config_test.yaml"

# Disable automatic application startup for tests
config :hag_ex, :start_application, false

# Configure ExUnit to capture less IO so debug logs are visible
config :ex_unit,
  capture_log: false
