defmodule ExUpcloud.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_upcloud,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      package: package(),
      description: description(),
      deps: deps(),
      name: "ex_upcloud",
      source_url: "https://github.com/twine-se/ex_upcloud"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5.6"},
      {:styler, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    """
    An unofficial client for the Upcloud API.
    """
  end

  defp package do
    [
      name: "ex_upcloud",
      licenses: ["MIT"],
      files: ["lib", "mix.exs", "README.md"],
      maintainers: ["Fredrik Westmark"],
      links: %{"GitHub" => "https://github.com/twine-se/ex_upcloud"}
    ]
  end
end
