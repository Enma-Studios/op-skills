# op_skills

HoweCo Machinery field-service agent pack for Operately.

**Phase 1 ships the Billing Clerk agent**: it turns a completed field-service
work order into a QuickBooks invoice draft, runs deterministic self-checks on
the draft, and waits for a human approval before anything is written to
QuickBooks. The agent never sends invoices.

This package is standalone: it does not depend on Operately or reference any
Operately modules. The host (Operately) consumes it as a Mix dependency and
provides all outside capabilities through the `OpSkills.Host` behaviour.

No Trello, Zapier, or other third-party integrations in this pack.

## Install

Path dependency for local development (from the Operately repo):

```elixir
# mix.exs
{:op_skills, path: "../op-skills"}
```

Git dependency for production:

```elixir
{:op_skills, git: "https://github.com/howeco/op-skills.git", branch: "main"}
```

Then `mix deps.get`.

## Manifest

Operately discovers what this pack offers through the manifest — plain maps
with atom keys, no shared structs required:

```elixir
OpSkills.manifest()
#=> %{
#     name: "op_skills",
#     version: "0.1.0",
#     pack: "howeco-field-service",
#     agents: [...],
#     tools: [...]
#   }

OpSkills.Manifest.billing_clerk()
#=> %{
#     id: "billing-clerk",
#     skill: "billing-clerk",
#     skill_module: OpSkills.Skills.BillingClerk,
#     allowed_tools: ["invoice_checks", "request_approval"],
#     risk: :write,
#     requires_approval: true,
#     approval: %{action: "quickbooks_create_invoice", blocking: true},
#     ...
#   }
```

The agent entry names its allowed tools and marks every QuickBooks write as
blocking-approval. Tools implement the `OpSkills.Tool` behaviour; the host
decides what actually executes and never lets a tool read a secret directly.

## Invoice self-checks

`OpSkills.Checks.Invoice.run/1` takes plain maps (work order, invoice draft,
existing QBO invoice data — atoms or string keys both work) and returns:

```elixir
%{
  passed: true | false,
  checks: [%{key: "line_item_total", status: :pass | :fail | :warning, message: "..."}],
  issues: ["..."],
  summary: "human-readable one-liner for the approver"
}
```

All money is integer cents — no floats. The checks are deterministic and
side-effect free.

## Host capabilities

Tools never hold secrets or open network connections themselves. A host
implements `OpSkills.Host`:

- `fetch_secret/1` — hand a secret to the tool at run time
- `request/1` — execute an HTTP/API request descriptor with host auth
- `audit/1` — append to the host audit log
- `request_approval/1` — route an approval to a human, returns a reference
- `notify/2` — send a notification

## Secrets

Secrets are supplied by the host at run time via `fetch_secret/1`. Nothing is
stored, logged, or committed in this package. `.env`, `*.keys`, and
`priv/demo/` are git-ignored; tests use synthetic fixtures only.

## Test

```
mix test
```

## Status

Bootstrap release. Phase 1 tooling (`invoice_checks`, `request_approval`) is
real and tested; QuickBooks HTTP clients arrive behind the host `request/1`
descriptor in a later phase.
