defmodule Defdo.Tenant.Boundary.MixProject do
  use Mix.Project

  @version "0.1.0"
  @organization "defdo"
  @source_url "https://github.com/defdo-dev/defdo_tenant_boundary"

  def project do
    [
      app: :defdo_tenant_boundary,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),
      docs: docs(),
      package: package(),
      name: "Defdo.Tenant.Boundary",
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Defdo.Tenant.Boundary.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:defdo_tenant, path: "../defdo_tenant"},
      {:oban, "~> 2.17"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  def docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      groups_for_modules: [
        "Oban": ~r/^Defdo\.Tenant\.(Oban|Worker)$/,
        "PubSub": ~r/^Defdo\.Tenant\.PubSub/,
        "GenServer": ~r/^Defdo\.Tenant\.GenServer/,
        "Webhook": ~r/^Defdo\.Tenant\.Webhook/
      ],
      source_url_pattern: "#{@source_url}/blob/main/%{path}#L%{line}"
    ]
  end

  defp package do
    [
      organization: @organization,
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md),
      description: "Cross-process tenant boundary wrappers for the Defdo ecosystem — Oban, GenServer, PubSub, Webhook.",
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
