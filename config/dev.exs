import Config

# Configure logger for development
config :logger, level: :debug

# Development specific configuration
config :hag_ex,
  config_file: "config/hvac_config_dev.yaml"
