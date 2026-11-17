defmodule OpSkills.Checks.Invoice do
  @moduledoc """
  Deterministic, side-effect-free self-checks for a Billing Clerk invoice
  draft, following James's invoice standards: the draft must tell the whole
  story (complaint, diagnosis, repair, outcome), justify its labor, and only
  bill what the work order supports.

  Input and output are plain maps so a host (Operately) can call this without
  sharing structs. Keys may be atoms or strings.

  ## Expected input

      %{
        work_order: %{
          id: "WO-1042",
          customer: %{name: "Acme Foods", billing_entity: "Acme Foods Inc."},
          machine: %{id: "PRESS-07", model: "Itoh 40T", serial: "IT-88231"},
          po_number: "PO-3311",                        # optional
          receipts: [%{...}],                          # optional; presence is checked
          parts: [%{name: "Bearing 6204", quantity: 2}],
          checklist: [%{task: "Replace bearing", part: "Bearing 6204"}],
          time_entries: [%{technician: "J. Howe", hours: 1.5}]
        },
        invoice_draft: %{
          bill_to: "Acme Foods Inc.",
          narrative:
            "Complaint: press jamming. Diagnosis: ... Repair: ... Outcome: ...",
          labor_hours: 2.5,
          total_cents: 41_300,
          line_items: [
            %{kind: :labor, description: "Repair press", amount_cents: 24_000},
            %{kind: :parts, description: "Bearing 6204", amount_cents: 17_300}
          ],
          po_number: "PO-3311"                         # optional
        },
        existing_invoice: nil
        # or %{qbo_id: "QBO-771", status: "draft", work_order_id: "WO-1042",
        #     system_owned: false}
      }

  ## Result

      %{
        passed: true,
        checks: [%{key: "line_item_total", status: :pass, message: "..."}],
        issues: [],
        summary: "All 8 checks passed. Invoice draft is ready for human approval."
      }

  `passed` is false when any check fails; warnings surface in `issues` but do
  not block. All money is integer cents — floats are rejected.

  ## Existing QuickBooks invoices

  Operately's system-owned invoice for the same work order is **updated,
  never duplicated**: `existing_invoice` with `system_owned: true` and a
  matching `work_order_id` passes (a placeholder still warns that its
  contents will be replaced). Without the flag, any active invoice for the
  work order is a duplicate failure, and a placeholder must be replaced by a
  human before billing.
  """

  @type status :: :pass | :fail | :warning
  @type check :: %{key: String.t(), status: status(), message: String.t()}
  @type result :: %{
          passed: boolean(),
          checks: [check()],
          issues: [String.t()],
          summary: String.t()
        }

  @sections ~w(complaint diagnosis repair outcome)a

  @spec run(map()) :: result()
  def run(input) when is_map(input) do
    work_order = fetch(input, :work_order) || %{}
    draft = fetch(input, :invoice_draft) || %{}

    checks = [
      required_fields(work_order, draft),
      narrative_sections(draft),
      line_item_totals(draft),
      labor_hours(work_order, draft),
      parts_coverage(work_order, draft),
      qbo_invoice_state(input, work_order),
      receipts_and_pos(work_order, draft),
      billing_entity(work_order, draft)
    ]

    build_result(checks)
  end

  # ── individual checks ──────────────────────────────────────────────────

  defp required_fields(work_order, draft) do
    customer = fetch(work_order, :customer) || %{}
    machine = fetch(work_order, :machine) || %{}

    required = %{
      "work_order.id" => fetch(work_order, :id),
      "work_order.customer.name" => fetch(customer, :name),
      "work_order.machine.id" => fetch(machine, :id),
      "invoice_draft.narrative" => fetch(draft, :narrative)
    }

    missing = for {path, value} <- required, blank?(value), do: path

    case missing do
      [] ->
        check(
          "required_fields",
          :pass,
          "Work order, customer, machine, and narrative fields are present."
        )

      _ ->
        check("required_fields", :fail, "Missing required fields: #{Enum.join(missing, ", ")}.")
    end
  end

  defp narrative_sections(draft) do
    missing_message =
      "Narrative must contain complaint, diagnosis, repair, and outcome sections."

    case fetch(draft, :narrative) do
      nil ->
        check("narrative_sections", :fail, missing_message)

      narrative when is_map(narrative) ->
        missing = for section <- @sections, blank?(fetch(narrative, section)), do: section
        section_check(missing)

      narrative when is_binary(narrative) ->
        lowered = String.downcase(narrative)

        missing =
          for section <- @sections, not String.contains?(lowered, to_string(section)), do: section

        section_check(missing)

      _other ->
        check("narrative_sections", :fail, missing_message)
    end
  end

  defp section_check([]),
    do:
      check(
        "narrative_sections",
        :pass,
        "Narrative has complaint, diagnosis, repair, and outcome sections."
      )

  defp section_check(missing),
    do:
      check(
        "narrative_sections",
        :fail,
        "Narrative missing sections: #{Enum.map_join(missing, ", ", &to_string/1)}."
      )

  defp line_item_totals(draft) do
    total = fetch(draft, :total_cents)
    items = fetch(draft, :line_items) || []

    cond do
      not money?(total) ->
        check(
          "line_item_total",
          :fail,
          "invoice_draft.total_cents must be an integer number of cents (no floats)."
        )

      not is_list(items) or items == [] ->
        check("line_item_total", :fail, "Invoice draft has no line items.")

      true ->
        bad = Enum.find(items, &(not money?(fetch(&1, :amount_cents))))

        if bad do
          check(
            "line_item_total",
            :fail,
            "Every line item amount_cents must be an integer number of cents (no floats)."
          )
        else
          summed = Enum.sum(Enum.map(items, &fetch(&1, :amount_cents)))

          if summed == total do
            check(
              "line_item_total",
              :pass,
              "Line items sum to #{summed} cents and match the declared total."
            )
          else
            check(
              "line_item_total",
              :fail,
              "Line items sum to #{summed} cents but the declared total is #{total} cents."
            )
          end
        end
    end
  end

  defp labor_hours(work_order, draft) do
    declared = fetch(draft, :labor_hours)
    entries = fetch(work_order, :time_entries) || []

    cond do
      not hours?(declared) ->
        check("labor_hours", :fail, "invoice_draft.labor_hours must be a non-negative number.")

      not is_list(entries) ->
        check("labor_hours", :fail, "work_order.time_entries must be a list.")

      true ->
        logged = Enum.sum(for entry <- entries, hours?(hours = fetch(entry, :hours)), do: hours)

        cond do
          within?(declared, logged) and logged == 0 ->
            check("labor_hours", :pass, "No labor billed.")

          within?(declared, logged) ->
            check(
              "labor_hours",
              :pass,
              "Labor hours (#{num(declared)}h) match the #{num(logged)}h logged across #{length(entries)} time entries."
            )

          true ->
            check(
              "labor_hours",
              :fail,
              "Labor hours (#{num(declared)}h) do not match the #{num(logged)}h of logged time entries."
            )
        end
    end
  end

  defp parts_coverage(work_order, draft) do
    items = fetch(draft, :line_items) || []

    invoice_parts =
      for item <- items, part_line?(item), name = item_name(item), do: normalize(name)

    known = work_order_parts(work_order) |> MapSet.to_list()
    matches = Enum.map(invoice_parts, fn line -> {line, match_part(line, known)} end)

    unknown =
      matches
      |> Enum.filter(fn {_line, match} -> is_nil(match) end)
      |> Enum.map(fn {line, _} -> line end)
      |> Enum.uniq()

    duplicate_names =
      matches
      |> Enum.reject(fn {_line, match} -> is_nil(match) end)
      |> Enum.group_by(fn {_line, match} -> match end)
      |> Enum.filter(fn {_match, lines} -> length(lines) > 1 end)
      |> Enum.map(fn {match, _} -> match end)

    cond do
      invoice_parts == [] ->
        check("parts_coverage", :pass, "No parts billed.")

      duplicate_names != [] ->
        check(
          "parts_coverage",
          :fail,
          "Duplicate part lines on the invoice: #{Enum.join(duplicate_names, ", ")}."
        )

      unknown != [] ->
        check(
          "parts_coverage",
          :fail,
          "Parts billed but not present on the work order: #{Enum.join(unknown, ", ")}."
        )

      true ->
        check(
          "parts_coverage",
          :pass,
          "All #{length(invoice_parts)} part line(s) appear in the work order."
        )
    end
  end

  # A model may describe a part as "Oil filter LF-3504, qty 1" while the work order
  # stores "Oil filter". Match the longest known name contained in the line.
  defp match_part(_line, []), do: nil

  defp match_part(line, known) do
    known
    |> Enum.sort_by(&String.length/1, :desc)
    |> Enum.find(&String.contains?(line, &1))
  end

  defp work_order_parts(work_order) do
    entries = (fetch(work_order, :parts) || []) ++ (fetch(work_order, :checklist) || [])

    names =
      for entry <- entries,
          is_map(entry),
          field <- [:name, :part_number, :part],
          value = fetch(entry, field),
          is_binary(value) do
        normalize(value)
      end

    MapSet.new(names)
  end

  defp qbo_invoice_state(input, work_order) do
    case fetch(input, :existing_invoice) do
      nil ->
        check(
          "qbo_invoice_state",
          :pass,
          "No existing QuickBooks invoice found for this work order."
        )

      existing when is_map(existing) ->
        qbo_id = fetch(existing, :qbo_id) || fetch(existing, :id) || "unknown"
        status = status_string(fetch(existing, :status))
        wo_id = fetch(work_order, :id)
        system_owned? = fetch(existing, :system_owned) == true
        same_work_order? = wo_id != nil and fetch(existing, :work_order_id) == wo_id
        active? = status not in ~w(void cancelled deleted)

        cond do
          status == "placeholder" and not system_owned? ->
            check(
              "qbo_invoice_state",
              :fail,
              "Placeholder QuickBooks invoice (#{qbo_id}) exists — it must be replaced, not duplicated."
            )

          status == "placeholder" ->
            check(
              "qbo_invoice_state",
              :warning,
              "System-owned placeholder QuickBooks invoice (#{qbo_id}) exists — the approved draft replaces its contents, never duplicates it."
            )

          same_work_order? and active? and system_owned? ->
            check(
              "qbo_invoice_state",
              :pass,
              "The approved draft updates the system-owned QuickBooks invoice #{qbo_id} for work order #{wo_id} — it will not be duplicated."
            )

          same_work_order? and active? ->
            check(
              "qbo_invoice_state",
              :fail,
              "QuickBooks invoice #{qbo_id} already exists for work order #{wo_id}."
            )

          true ->
            check(
              "qbo_invoice_state",
              :pass,
              "Existing QuickBooks invoice #{qbo_id} does not block this draft."
            )
        end

      _other ->
        check("qbo_invoice_state", :fail, "existing_invoice must be a map or nil.")
    end
  end

  defp receipts_and_pos(work_order, draft) do
    receipts = fetch(work_order, :receipts) || []
    wo_po = fetch(work_order, :po_number) || fetch(work_order, :po)
    draft_po = fetch(draft, :po_number) || fetch(draft, :po)

    gaps = []

    gaps =
      if parts_expected?(work_order, draft) and receipts == [] do
        ["no receipts on file for billed parts" | gaps]
      else
        gaps
      end

    gaps =
      if blank?(wo_po) do
        ["no PO number on the work order" | gaps]
      else
        gaps
      end

    gaps =
      if not blank?(wo_po) and blank?(draft_po) do
        ["work order PO #{wo_po} is not referenced on the invoice draft" | gaps]
      else
        gaps
      end

    case gaps do
      [] ->
        check("receipts_and_pos", :pass, "Receipts and PO paperwork are in order.")

      _ ->
        check(
          "receipts_and_pos",
          :warning,
          "Paperwork gaps: #{Enum.join(Enum.reverse(gaps), "; ")}."
        )
    end
  end

  defp billing_entity(work_order, draft) do
    customer = fetch(work_order, :customer) || %{}
    bill_to = fetch(draft, :bill_to)
    expected = fetch(customer, :billing_entity)

    cond do
      blank?(bill_to) ->
        check("billing_entity", :fail, "Invoice draft has no bill_to.")

      blank?(expected) ->
        check(
          "billing_entity",
          :warning,
          "Work order has no customer billing entity to verify bill_to against."
        )

      normalize(bill_to) == normalize(expected) ->
        check("billing_entity", :pass, "Bill-to matches the customer billing entity.")

      true ->
        check(
          "billing_entity",
          :fail,
          "Billing entity mismatch: invoice is billed to #{bill_to} but the work order says #{expected}."
        )
    end
  end

  # ── result assembly ────────────────────────────────────────────────────

  defp build_result(checks) do
    failures = for %{status: :fail, message: message} <- checks, do: message
    warnings = for %{status: :warning, message: message} <- checks, do: message
    issues = failures ++ warnings

    summary =
      cond do
        failures != [] ->
          "#{length(failures)} of #{length(checks)} checks failed. #{Enum.join(failures, " ")}"

        warnings != [] ->
          "All #{length(checks)} checks passed with #{length(warnings)} warning(s). #{Enum.join(warnings, " ")}"

        true ->
          "All #{length(checks)} checks passed. Invoice draft is ready for human approval."
      end

    %{passed: failures == [], checks: checks, issues: issues, summary: summary}
  end

  # ── helpers ────────────────────────────────────────────────────────────

  defp check(key, status, message), do: %{key: key, status: status, message: message}

  defp fetch(nil, _key), do: nil

  defp fetch(map, key) when is_map(map) and is_atom(key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
  defp blank?(_), do: false

  defp money?(value), do: is_integer(value)
  defp hours?(value), do: is_number(value) and value >= 0
  defp within?(a, b), do: abs(a - b) < 0.01

  defp num(value) when is_integer(value), do: Integer.to_string(value)
  defp num(value) when is_float(value), do: Float.to_string(value)

  defp part_line?(item) do
    case fetch(item, :kind) do
      nil -> false
      kind -> kind |> to_string() |> String.downcase() |> then(&(&1 in ["parts", "part"]))
    end
  end

  defp item_name(item), do: fetch(item, :name) || fetch(item, :description) || "unnamed part line"

  defp parts_expected?(work_order, draft) do
    items = fetch(draft, :line_items) || []
    wo_parts = fetch(work_order, :parts) || []

    wo_parts != [] or Enum.any?(items, &part_line?/1)
  end

  defp status_string(nil), do: ""
  defp status_string(value) when is_binary(value), do: String.downcase(String.trim(value))
  defp status_string(value), do: value |> to_string() |> String.downcase()

  defp normalize(value), do: value |> to_string() |> String.trim() |> String.downcase()
end
