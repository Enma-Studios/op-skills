defmodule OpSkills.Tools.InvoiceChecks do
  @moduledoc """
  Runs the deterministic invoice self-checks (`OpSkills.Checks.Invoice`) on a
  draft. Read-only: it never contacts QuickBooks and never mutates anything.
  """

  @behaviour OpSkills.Tool

  alias OpSkills.Checks.Invoice

  @impl true
  def name, do: "invoice_checks"

  @impl true
  def description,
    do:
      "Runs deterministic invoice self-checks (required fields, narrative sections, totals, labor hours, parts coverage, QBO duplicates, receipts/POs, billing entity) and returns the structured result."

  @impl true
  def risk, do: :read

  @impl true
  def requires_approval?, do: false

  @impl true
  def schema do
    %{
      "type" => "object",
      "required" => ["work_order", "invoice_draft"],
      "properties" => %{
        "work_order" => %{"type" => "object"},
        "invoice_draft" => %{"type" => "object"},
        "existing_invoice" => %{"oneOf" => [%{"type" => "object"}, %{"type" => "null"}]}
      }
    }
  end

  @impl true
  def run(args, _host) when is_map(args), do: {:ok, Invoice.run(args)}
  def run(args, _host), do: {:error, {:invalid_args, args}}
end
