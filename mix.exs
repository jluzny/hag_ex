defmodule HagEx.MixProject do
  use Mix.Project

  def project do
    [
      app: :hag_ex,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      compilers: [:finitomata] ++ Mix.compilers(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger, :inets, :ssl],
      mod: {HagEx.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # State machines and workflows
      {:finitomata, "~> 0.34.0"},
      {:jido, "~> 1.2.0"},

      # Configuration and serialization
      {:yaml_elixir, "~> 2.9"},
      {:jason, "~> 1.4"},

      # HTTP and WebSocket clients
      {:websockex, "~> 0.4"},
      {:req, "~> 0.5"},

      # Development and testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end
end
