import Config

# Configure logger for production
config :logger, level: :debug

# Production specific configuration
config :hag_ex,
  config_file: "config/hvac_config.yaml"
