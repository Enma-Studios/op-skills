defmodule OpSkills.MixProject do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :op_skills,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:req, "~> 0.5"},
      {:jido, "~> 2.4"},
      {:jido_ai, "~> 2.4"},
      {:bypass, "~> 2.1", only: :test}
    ]
  end

  defp description do
    "HoweCo Machinery field-service agent pack: skill manifests, invoice self-checks, and host capability contracts for the Billing Clerk agent."
  end

  defp package do
    [
      files: ["lib", "priv", "test", "README.md", "mix.exs"],
      licenses: ["Apache-2.0"],
      links: %{}
    ]
  end
end
