defmodule Pack.MixProject do
  use Mix.Project

  def project do
    [
      app: :packer,
      version: "0.1.0",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:remix, "~> 0.0.2", only: [:dev]},
      {:brotli, "~> 0.2.0"},
      {:zstd, "~> 0.2.0"}
    ]
  end
end
