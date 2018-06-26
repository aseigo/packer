defmodule Pack.MixProject do
  use Mix.Project

  def project do
    [
      app: :packer,
      version: "0.0.4",
      elixir: "~> 1.6",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: ["coveralls": :test, "coveralls.detail": :test, "coveralls.html": :test]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:zstd, "~> 0.2.0"},
      {:remix, "~> 0.0.2", only: :dev},
      {:ex_doc, "~> 0.18.3", only: :dev},
      {:excoveralls, "~> 0.9.1", only: :test},
    ]
  end

  defp description() do
    "A space-efficient term serializer, with specific attention paid to handling large, nested / repetitive terms."
  end

  defp package() do
    [
      # These are the default files included in the package
      files: ["lib", "mix.exs", "README*", "LICENSE*"],
      maintainers: ["Aaron Seigo"],
      licenses: ["Apache 2.0"],
      links: %{"GitHub" => "https://github.com/aseigo/packer"}
    ]
  end
end
