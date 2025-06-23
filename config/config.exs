import Config

# Common configuration for all environments
config :hag_ex,
  # Configuration file path
  config_file: "config/hvac_config.yaml"

# Import environment specific config
import_config "#{config_env()}.exs"
