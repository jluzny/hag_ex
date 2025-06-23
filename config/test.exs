import Config

# Configure logger for test
config :logger, level: :warning

# Test specific configuration - don't start application automatically
config :hag_ex,
  config_file: "config/hvac_config_test.yaml"

# Disable automatic application startup for tests
config :hag_ex, :start_application, false
