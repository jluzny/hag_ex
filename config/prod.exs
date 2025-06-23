import Config

# Configure logger for production
config :logger, level: :info

# Production specific configuration
config :hag_ex,
  config_file: "config/hvac_config.yaml"
