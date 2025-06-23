import Config

# Configure logger for test
config :logger, level: :warn

# Test specific configuration
config :hag_ex,
  config_file: "config/hvac_config_test.yaml"
