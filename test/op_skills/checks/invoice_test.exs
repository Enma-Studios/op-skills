defmodule OpSkills.Checks.InvoiceTest do
  use ExUnit.Case, async: true

  alias OpSkills.Checks.Invoice

  # Synthetic fixture — no real customer data.
  defp valid_input do
    %{
      work_order: %{
        id: "WO-1042",
        customer: %{name: "Acme Foods", billing_entity: "Acme Foods Inc."},
        machine: %{id: "PRESS-07", model: "Itoh 40T", serial: "IT-88231"},
        po_number: "PO-3311",
        receipts: [%{file: "receipt-01.pdf", total_cents: 17_300}],
        parts: [%{name: "Bearing 6204", quantity: 2}],
        checklist: [%{task: "Replace main bearing", part: "Bearing 6204"}],
        time_entries: [
          %{technician: "J. Howe", hours: 1.5},
          %{technician: "R. Okafor", hours: 1.0}
        ]
      },
      invoice_draft: %{
        bill_to: "Acme Foods Inc.",
        narrative: """
        Complaint: press jamming on every third cycle.
        Diagnosis: main bearing scored, shaft runout beyond spec.
        Repair: replaced main bearing, realigned shaft, torqued to spec.
        Outcome: ran 20 cycles, no jamming, machine released to production.
        """,
        labor_hours: 2.5,
        total_cents: 41_300,
        po_number: "PO-3311",
        line_items: [
          %{kind: :labor, description: "Bearing replacement, 2.5h", amount_cents: 24_000},
          %{kind: :parts, description: "Bearing 6204", amount_cents: 17_300}
        ]
      },
      existing_invoice: nil
    }
  end

  defp status_for(result, key) do
    check = Enum.find(result.checks, &(&1.key == key))
    {check.status, check.message}
  end

  defp change(input, path, value) do
    put_in(input, Enum.map(path, &Access.key(&1)), value)
  end

  test "passes a complete, consistent work order" do
    result = Invoice.run(valid_input())

    assert result.passed
    assert result.issues == []
    assert Enum.all?(result.checks, &(&1.status == :pass))
    assert length(result.checks) == 8
    assert result.summary =~ "ready for human approval"
  end

  test "accepts string keys and a map-style narrative" do
    input =
      valid_input()
      |> Map.new(fn {k, v} -> {Atom.to_string(k), v} end)
      |> Map.update("invoice_draft", %{}, fn draft ->
        draft = Map.new(draft, fn {k, v} -> {Atom.to_string(k), v} end)

        Map.put(draft, "narrative", %{
          complaint: "Press jamming on every third cycle.",
          diagnosis: "Main bearing scored.",
          repair: "Replaced main bearing.",
          outcome: "Ran 20 cycles clean."
        })
      end)

    assert Invoice.run(input).passed
  end

  test "empty input fails every blocking check without crashing" do
    result = Invoice.run(%{})

    refute result.passed
    keys = Enum.map(result.checks, & &1.key)

    assert Enum.sort(keys) ==
             Enum.sort(
               ~w(required_fields narrative_sections line_item_total labor_hours parts_coverage qbo_invoice_state receipts_and_pos billing_entity)
             )

    for %{status: status, message: message} <- result.checks, status != :pass do
      assert is_binary(message) and message != ""
    end

    assert result.summary =~ "checks failed"
  end

  test "flags missing required fields individually" do
    input = valid_input() |> change([:work_order, :machine, :id], nil)
    result = Invoice.run(input)

    {status, message} = status_for(result, "required_fields")
    assert status == :fail
    assert message =~ "work_order.machine.id"
  end

  test "flags blank narrative as missing" do
    input = change(valid_input(), [:invoice_draft, :narrative], "   ")
    {status, message} = status_for(Invoice.run(input), "required_fields")

    assert status == :fail
    assert message =~ "invoice_draft.narrative"
  end

  test "flags narrative missing sections" do
    input =
      change(
        valid_input(),
        [:invoice_draft, :narrative],
        "Complaint: jamming. Repair: fixed it. Outcome: good."
      )

    {status, message} = status_for(Invoice.run(input), "narrative_sections")

    assert status == :fail
    assert message =~ "diagnosis"
  end

  test "flags line item totals that do not match the declared total" do
    input = change(valid_input(), [:invoice_draft, :total_cents], 41_999)
    {status, message} = status_for(Invoice.run(input), "line_item_total")

    assert status == :fail
    assert message =~ "41_300" or message =~ "41300"
  end

  test "rejects float money" do
    input = change(valid_input(), [:invoice_draft, :total_cents], 41_300.0)
    {status, message} = status_for(Invoice.run(input), "line_item_total")

    assert status == :fail
    assert message =~ "integer"
  end

  test "rejects a float amount on a line item" do
    input =
      valid_input()
      |> change([:invoice_draft, :line_items], [
        %{kind: :labor, description: "Labor", amount_cents: 24_000.5},
        %{kind: :parts, description: "Bearing 6204", amount_cents: 17_300}
      ])

    {status, message} = status_for(Invoice.run(input), "line_item_total")

    assert status == :fail
    assert message =~ "integer"
  end

  test "flags labor hours that do not match time entries" do
    input = change(valid_input(), [:invoice_draft, :labor_hours], 3.0)
    {status, message} = status_for(Invoice.run(input), "labor_hours")

    assert status == :fail
    assert message =~ "3.0h"
    assert message =~ "2.5h"
  end

  test "flags a part on the invoice that is not on the work order" do
    input =
      valid_input()
      |> change([:invoice_draft, :line_items], [
        %{kind: :labor, description: "Labor", amount_cents: 24_000},
        %{kind: :parts, description: "Capacitor 40uF", amount_cents: 17_300}
      ])

    {status, message} = status_for(Invoice.run(input), "parts_coverage")

    assert status == :fail
    assert message =~ "capacitor 40uf"
  end

  test "flags duplicate part lines" do
    input =
      valid_input()
      |> change([:invoice_draft, :line_items], [
        %{kind: :labor, description: "Labor", amount_cents: 12_000},
        %{kind: :parts, description: "Bearing 6204", amount_cents: 17_300},
        %{kind: :parts, description: "bearing 6204", amount_cents: 17_300}
      ])
      |> change([:invoice_draft, :total_cents], 46_600)

    {status, message} = status_for(Invoice.run(input), "parts_coverage")

    assert status == :fail
    assert message =~ "Duplicate part lines"
  end

  test "matches a part line that includes the part number and quantity" do
    input =
      valid_input()
      |> change([:invoice_draft, :line_items], [
        %{kind: :labor, description: "Labor", amount_cents: 24_000},
        %{kind: :part, description: "Bearing 6204, qty 2", amount_cents: 17_300}
      ])

    result = Invoice.run(input)
    assert result.passed
    assert status_for(result, "parts_coverage") |> elem(0) == :pass
  end

  test "flags duplicate part lines when both descriptions match the same work-order part" do
    input =
      valid_input()
      |> change([:invoice_draft, :line_items], [
        %{kind: :labor, description: "Labor", amount_cents: 12_000},
        %{kind: :parts, description: "Bearing 6204", amount_cents: 17_300},
        %{kind: :parts, description: "Bearing 6204, qty 2", amount_cents: 17_300}
      ])
      |> change([:invoice_draft, :total_cents], 46_600)

    {status, message} = status_for(Invoice.run(input), "parts_coverage")

    assert status == :fail
    assert message =~ "Duplicate part lines"
  end

  test "flags a placeholder QBO invoice" do
    input =
      change(valid_input(), [:existing_invoice], %{
        qbo_id: "QBO-771",
        status: "placeholder",
        work_order_id: "WO-0000"
      })

    {status, message} = status_for(Invoice.run(input), "qbo_invoice_state")

    assert status == :fail
    assert message =~ "Placeholder"
    assert message =~ "QBO-771"
  end

  test "a system-owned placeholder warns that the draft replaces it" do
    input =
      change(valid_input(), [:existing_invoice], %{
        qbo_id: "QBO-771",
        status: "placeholder",
        work_order_id: "WO-1042",
        system_owned: true
      })

    result = Invoice.run(input)
    {status, message} = status_for(result, "qbo_invoice_state")

    assert status == :warning
    assert message =~ "replaces its contents"
    assert message =~ "never duplicates"
    assert result.passed
    assert Enum.any?(result.issues, &(&1 =~ "placeholder"))
  end

  test "flags an existing QBO invoice for the same work order" do
    input =
      change(valid_input(), [:existing_invoice], %{
        qbo_id: "QBO-772",
        status: "draft",
        work_order_id: "WO-1042"
      })

    {status, message} = status_for(Invoice.run(input), "qbo_invoice_state")

    assert status == :fail
    assert message =~ "already exists"
  end

  test "passes a system-owned QBO invoice for the same work order as an update" do
    input =
      change(valid_input(), [:existing_invoice], %{
        qbo_id: "QBO-772",
        status: "draft",
        work_order_id: "WO-1042",
        system_owned: true
      })

    result = Invoice.run(input)
    {status, message} = status_for(result, "qbo_invoice_state")

    assert status == :pass
    assert message =~ "updates"
    assert message =~ "not be duplicated"
    assert result.passed
  end

  test "system_owned: false still fails as a duplicate" do
    input =
      change(valid_input(), [:existing_invoice], %{
        qbo_id: "QBO-772",
        status: "draft",
        work_order_id: "WO-1042",
        system_owned: false
      })

    {status, _message} = status_for(Invoice.run(input), "qbo_invoice_state")

    assert status == :fail
  end

  test "ignores a QBO invoice for a different work order" do
    input =
      change(valid_input(), [:existing_invoice], %{
        qbo_id: "QBO-773",
        status: "paid",
        work_order_id: "WO-0999"
      })

    assert Invoice.run(input).passed
  end

  test "surfaces missing receipts as a warning without blocking" do
    input = change(valid_input(), [:work_order, :receipts], [])
    result = Invoice.run(input)

    {status, message} = status_for(result, "receipts_and_pos")
    assert status == :warning
    assert message =~ "no receipts on file"
    assert result.passed
    assert Enum.any?(result.issues, &(&1 =~ "receipts"))
  end

  test "surfaces a missing PO as a warning" do
    input = change(valid_input(), [:work_order, :po_number], nil)
    result = Invoice.run(input)

    {status, message} = status_for(result, "receipts_and_pos")
    assert status == :warning
    assert message =~ "no PO number"
    assert result.passed
  end

  test "warns when the work order PO is not on the draft" do
    input = change(valid_input(), [:invoice_draft, :po_number], nil)
    {status, message} = status_for(Invoice.run(input), "receipts_and_pos")

    assert status == :warning
    assert message =~ "not referenced"
  end

  test "flags a billing entity mismatch" do
    input = change(valid_input(), [:invoice_draft, :bill_to], "Acme Foods LLC")
    {status, message} = status_for(Invoice.run(input), "billing_entity")

    assert status == :fail
    assert message =~ "mismatch"
    refute Invoice.run(input).passed
  end

  test "fails when the draft has no bill_to" do
    input = change(valid_input(), [:invoice_draft, :bill_to], "")
    {status, _message} = status_for(Invoice.run(input), "billing_entity")

    assert status == :fail
  end

  test "warns when the work order has no billing entity to compare" do
    input = change(valid_input(), [:work_order, :customer, :billing_entity], nil)
    {status, message} = status_for(Invoice.run(input), "billing_entity")

    assert status == :warning
    assert message =~ "no customer billing entity"
  end
end
