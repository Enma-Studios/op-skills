defmodule OpSkills.Skills.BillingClerk do
  @moduledoc """
  Phase-1 skill: turn a completed work order into a self-checked invoice
  draft and wait for human approval before any QuickBooks write.

  Implements the `Jido.AI.Skill` behaviour with the spec metadata sourced from
  `OpSkills.Manifest` and the body loaded from this package's
  `priv/skills/howeco/billing-clerk/SKILL.md` at run time, so the file is the
  single source of instructions. (`use Jido.AI.Skill` would bake a compile-time
  body path that breaks when Operately packages this as a dependency or
  release, so the behaviour is implemented directly.)
  """

  @behaviour Jido.AI.Skill

  @skill_md "priv/skills/howeco/billing-clerk/SKILL.md"
  @manifest OpSkills.Manifest.billing_clerk()

  @impl Jido.AI.Skill
  def manifest do
    %Jido.AI.Skill.Spec{
      name: @manifest.id,
      description: @manifest.summary,
      license: "Apache-2.0",
      metadata: %{
        risk: @manifest.risk,
        requires_approval: @manifest.requires_approval,
        approval: @manifest.approval
      },
      allowed_tools: @manifest.allowed_tools,
      source: {:module, __MODULE__},
      body_ref: {:file, Application.app_dir(:op_skills, @skill_md)},
      actions: [],
      plugins: [],
      tags: [:howeco, :billing]
    }
  end

  @impl Jido.AI.Skill
  def body, do: Jido.AI.Skill.body(manifest())

  @impl Jido.AI.Skill
  def allowed_tools, do: manifest().allowed_tools

  @impl Jido.AI.Skill
  def actions, do: manifest().actions

  @impl Jido.AI.Skill
  def plugins, do: manifest().plugins
end
