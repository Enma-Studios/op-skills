defmodule OpSkills.Skills.BillingClerkTest do
  use ExUnit.Case, async: true

  alias OpSkills.Manifest
  alias OpSkills.Skills.BillingClerk

  test "resolves through the Jido skill API and stays consistent with the manifest" do
    # Jido.AI.Skill.resolve/1 checks function_exported?/3, which does not
    # auto-load the module; after a recompile purge the module may not be
    # loaded yet, so load it explicitly first.
    Code.ensure_loaded!(BillingClerk)

    assert {:ok, spec} = Jido.AI.Skill.resolve(BillingClerk)
    assert spec.name == Manifest.billing_clerk().id
    assert spec.description == Manifest.billing_clerk().summary
    assert spec.allowed_tools == Manifest.billing_clerk().allowed_tools
    assert Jido.AI.Skill.allowed_tools(BillingClerk) == Manifest.billing_clerk().allowed_tools
    assert Jido.AI.Skill.body(BillingClerk) == BillingClerk.body()
  end

  test "body is loaded from the packaged SKILL.md and encodes James's invoice style" do
    body = BillingClerk.body()

    for section <- ~w(complaint diagnosis repair outcome) do
      assert body =~ section
    end

    assert body =~ "never send" or body =~ "You never send"
    assert body =~ "QuickBooks"
    assert body =~ "request_approval"
  end

  test "tool callbacks expose the spec data" do
    assert BillingClerk.actions() == []
    assert BillingClerk.plugins() == []
  end
end
