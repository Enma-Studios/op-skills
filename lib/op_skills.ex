defmodule OpSkills do
  @moduledoc """
  HoweCo Machinery field-service agent pack.

  Phase 1 ships the Billing Clerk agent: it turns a completed work order into
  a self-checked QuickBooks invoice draft (`OpSkills.Checks.Invoice`) and waits
  for human approval before any write. The package is standalone — no
  Operately modules, no dependencies on the host. The host implements
  `OpSkills.Host` to supply secrets, HTTP, audit, approvals, and notifications,
  and reads `manifest/0` to discover the agents, tools, and approval gates.

  Tools never hold secrets or open connections; they act only through the host.
  """

  @doc "The pack manifest (delegates to `OpSkills.Manifest.pack/0`)."
  defdelegate manifest(), to: OpSkills.Manifest, as: :pack
end
