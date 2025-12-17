defmodule Pizza.MixProject do
  use Mix.Project

  def project do
    [
      app: :pizza,
      version: "0.1.0",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {Pizza.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:uuid, "~> 1.1"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_dynamo, "~> 4.2"},
      {:jason, "~> 1.4"},
      {:hackney, "~> 1.25"}
    ]
  end

  defp escript do
    [main_module: Pizza.Application]
  end
end
