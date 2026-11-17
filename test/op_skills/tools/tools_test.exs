defmodule TestHost do
  @moduledoc "Minimal in-memory host for tool tests."

  @behaviour OpSkills.Host

  def fetch_secret(_key), do: {:error, :not_used}
  def request(_descriptor), do: {:error, :not_used}

  def audit(event) do
    send(self(), {:audited, event})
    :ok
  end

  def request_approval(%{summary: summary}) do
    send(agent_pid(), {:approval_requested, summary})
    {:ok, "apr-123"}
  end

  def notify(recipient, message) do
    send(agent_pid(), {:notified, recipient, message})
    :ok
  end

  defp agent_pid, do: self()
end

defmodule DenyingHost do
  @behaviour OpSkills.Host
  def fetch_secret(_), do: {:error, :not_used}
  def request(_), do: {:error, :not_used}
  def audit(_), do: :ok
  def request_approval(_), do: {:error, :denied}
  def notify(_, _), do: :ok
end

defmodule OpSkills.Tools.RequestApprovalTest do
  use ExUnit.Case, async: true

  alias OpSkills.Tools.RequestApproval

  test "metadata marks it as the approval gate itself" do
    assert RequestApproval.name() == "request_approval"
    assert RequestApproval.risk() == :write
    refute RequestApproval.requires_approval?()
    assert is_map(RequestApproval.schema())
    assert "summary" in RequestApproval.schema()["required"]
  end

  test "routes the approval through the host, then audits and notifies" do
    args = %{summary: "Draft for WO-1042, 8/8 checks passed", draft: %{total_cents: 41_300}}

    assert {:ok, %{approval_ref: "apr-123"}} == RequestApproval.run(args, TestHost)

    assert_received {:approval_requested, "Draft for WO-1042, 8/8 checks passed"}
    assert_received {:audited, %{event: "approval_requested", approval_ref: "apr-123"}}
    assert_received {:notified, "invoice-approvers", message}
    assert message =~ "apr-123"
  end

  test "propagates host rejection" do
    assert {:error, :denied} == RequestApproval.run(%{summary: "x"}, DenyingHost)
  end

  test "rejects non-map args" do
    assert {:error, {:invalid_args, "nope"}} == RequestApproval.run("nope", TestHost)
  end
end

defmodule OpSkills.Tools.InvoiceChecksTest do
  use ExUnit.Case, async: true

  alias OpSkills.Tools.InvoiceChecks

  test "metadata: read-only, no approval needed" do
    assert InvoiceChecks.name() == "invoice_checks"
    assert InvoiceChecks.risk() == :read
    refute InvoiceChecks.requires_approval?()
    assert InvoiceChecks.schema()["required"] == ["work_order", "invoice_draft"]
  end

  test "schema is well-formed: no nested map under \"type\"" do
    schema = InvoiceChecks.schema()
    assert schema["type"] == "object"
    assert is_map(schema["properties"])
    refute Map.has_key?(schema["properties"]["existing_invoice"], "type")

    assert schema["properties"]["existing_invoice"]["oneOf"] == [
             %{"type" => "object"},
             %{"type" => "null"}
           ]

    # Every "type" value anywhere in the schema must be a JSON Schema type name.
    for %{"type" => type} <- all_schemas(schema) do
      assert is_binary(type) and
               type in ["object", "null", "string", "number", "boolean", "array"]
    end
  end

  defp all_schemas(schema) when is_map(schema) do
    [schema | Enum.flat_map(Map.values(schema), &all_schemas/1)]
  end

  defp all_schemas(list) when is_list(list), do: Enum.flat_map(list, &all_schemas/1)
  defp all_schemas(_other), do: []

  test "runs the checks and reports failures inside {:ok, _}" do
    assert {:ok, result} = InvoiceChecks.run(%{}, TestHost)
    refute result.passed
    assert length(result.checks) == 8
  end

  test "rejects non-map args" do
    assert {:error, {:invalid_args, nil}} == InvoiceChecks.run(nil, TestHost)
  end
end
