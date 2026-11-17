defmodule OpSkills.Tools.RequestApproval do
  @moduledoc """
  Asks the host to route an approval request to a human and records it in the
  audit log. This tool is the approval gate itself: it writes nothing to
  QuickBooks, so `requires_approval?/0` is false — running it *is* the
  request for approval.
  """

  @behaviour OpSkills.Tool

  @impl true
  def name, do: "request_approval"

  @impl true
  def description,
    do:
      "Requests human approval for an invoice draft before any QuickBooks write. Returns the approval reference the agent must wait on."

  @impl true
  def risk, do: :write

  @impl true
  def requires_approval?, do: false

  @impl true
  def schema do
    %{
      "type" => "object",
      "required" => ["summary"],
      "properties" => %{
        "summary" => %{
          "type" => "string",
          "description" => "Human-readable summary of the draft being approved."
        },
        "check_summary" => %{
          "type" => "string",
          "description" => "Outcome of the invoice self-checks, included in the notification."
        },
        "draft" => %{
          "type" => "object",
          "description" => "The full invoice draft payload for the approver."
        }
      }
    }
  end

  @impl true
  def run(args, host) when is_map(args) do
    summary = args |> fetch(:summary) |> present() || "Approval requested"
    check_summary = args |> fetch(:check_summary) |> present()

    request = %{subject: "Invoice draft approval", summary: summary, payload: fetch(args, :draft)}

    with {:ok, approval_ref} <- host.request_approval(request) do
      host.audit(%{event: "approval_requested", approval_ref: approval_ref, summary: summary})

      host.notify(
        "invoice-approvers",
        "Approval requested (#{approval_ref}): #{check_summary || summary}"
      )

      {:ok, %{approval_ref: approval_ref}}
    end
  end

  def run(args, _host), do: {:error, {:invalid_args, args}}

  defp fetch(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp present(nil), do: nil
  defp present(value) when is_binary(value), do: String.trim(value)
  defp present(value), do: to_string(value)
end
