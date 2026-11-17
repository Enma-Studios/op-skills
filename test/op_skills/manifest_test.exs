defmodule OpSkills.ManifestTest do
  use ExUnit.Case, async: true

  describe "pack/0" do
    test "describes the pack and lists the phase-1 agent" do
      pack = OpSkills.Manifest.pack()

      assert pack.name == "op_skills"
      assert is_binary(pack.version) and pack.version != ""
      assert pack.pack == "howeco-field-service"
      assert [clerk] = pack.agents
      assert clerk.id == "billing-clerk"
    end

    test "lists every tool with complete metadata" do
      tools = OpSkills.Manifest.pack().tools

      assert Enum.map(tools, & &1.name) == ["invoice_checks", "request_approval"]

      for tool <- tools do
        assert tool.risk in [:read, :write, :destructive]
        assert is_boolean(tool.requires_approval)
        assert is_binary(tool.description) and tool.description != ""
        assert is_map(tool.schema)
        assert tool.module in OpSkills.Manifest.tool_modules()
      end
    end
  end

  describe "billing_clerk/0" do
    test "is approval-gated for QuickBooks writes" do
      clerk = OpSkills.Manifest.billing_clerk()

      assert clerk.risk == :write
      assert clerk.requires_approval == true
      assert clerk.approval == %{action: "quickbooks_create_invoice", blocking: true}
    end

    test "allowed tools are unique and match the shipped tools" do
      clerk = OpSkills.Manifest.billing_clerk()

      assert clerk.allowed_tools == OpSkills.Manifest.allowed_tools()
      assert clerk.allowed_tools == Enum.uniq(clerk.allowed_tools)
      assert clerk.allowed_tools != []
    end

    test "checks_module runs the documented self-checks" do
      clerk = OpSkills.Manifest.billing_clerk()
      result = clerk.checks_module.run(%{})

      assert result.passed == false
      assert is_map(result)
    end

    test "top-level manifest/0 delegates to the pack" do
      assert OpSkills.manifest() == OpSkills.Manifest.pack()
    end
  end
end
