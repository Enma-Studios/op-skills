defmodule OpSkills.Manifest do
  @moduledoc """
  Data manifest of this agent pack.

  Operately reads these plain maps (atom keys, JSON-friendly values; `*_module`
  fields are atoms pointing at modules in this package) to discover the agents,
  their skills, allowed tools, and what needs human approval. Nothing here is
  executable logic: tools carry their own metadata via the `OpSkills.Tool`
  behaviour, and this module only assembles it.
  """

  alias OpSkills.Tools.{InvoiceChecks, RequestApproval}

  @tools [InvoiceChecks, RequestApproval]

  @doc "The full pack manifest: every agent and tool this package ships."
  @spec pack() :: map()
  def pack do
    %{
      name: "op_skills",
      version: to_string(Application.spec(:op_skills, :vsn)),
      pack: "howeco-field-service",
      agents: [billing_clerk()],
      tools: Enum.map(@tools, &tool_metadata/1)
    }
  end

  @doc "The phase-1 Billing Clerk agent entry."
  @spec billing_clerk() :: map()
  def billing_clerk do
    %{
      id: "billing-clerk",
      name: "Billing Clerk",
      skill: "billing-clerk",
      skill_module: OpSkills.Skills.BillingClerk,
      summary:
        "Turns a completed field-service work order into a self-checked QuickBooks invoice draft and waits for human approval before any write.",
      risk: :write,
      requires_approval: true,
      approval: %{action: "quickbooks_create_invoice", blocking: true},
      allowed_tools: Enum.map(@tools, & &1.name()),
      checks_module: OpSkills.Checks.Invoice
    }
  end

  @doc "Tool modules shipped in this pack, in manifest order."
  @spec tool_modules() :: [module()]
  def tool_modules, do: @tools

  @doc "Tool names the agents may call, for host-side gating."
  @spec allowed_tools() :: [String.t()]
  def allowed_tools, do: Enum.map(@tools, & &1.name())

  defp tool_metadata(mod) do
    %{
      name: mod.name(),
      description: mod.description(),
      risk: mod.risk(),
      requires_approval: mod.requires_approval?(),
      module: mod,
      schema: mod.schema()
    }
  end
end
