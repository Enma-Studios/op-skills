defmodule OpSkills.Host do
  @moduledoc """
  Capabilities a host application (e.g. Operately) must provide to run tools
  in this pack.

  Tools never read secrets and never open network connections themselves —
  everything that touches the outside world goes through the host, which owns
  secret storage, outbound auth, the audit log, the human approval workflow,
  and notifications. This behaviour has no implementation in this package; the
  host supplies one.
  """

  @typedoc "Opaque identifier of a pending approval, returned by the host."
  @type approval_ref :: String.t()

  @typedoc """
  Description of an outbound call the host should execute against one of its
  allowlisted integrations.

  `:system` names the integration (for example `"quickbooks"`), and
  `:company_id` / `:connection_id` scope it to the tenant's stored
  connection. The host only executes requests against systems it allowlists
  and connections it owns — never arbitrary URLs.
  """
  @type request_descriptor :: %{
          required(:method) => String.t(),
          required(:url) => String.t(),
          optional(:system) => String.t(),
          optional(:company_id) => String.t(),
          optional(:connection_id) => String.t(),
          optional(:headers) => map(),
          optional(:body) => map() | String.t()
        }

  @typedoc "What to route to a human approver."
  @type approval_request :: %{
          required(:subject) => String.t(),
          required(:summary) => String.t(),
          optional(:payload) => term()
        }

  @doc """
  Returns the secret stored by the host under `key`, or `{:error, reason}`.

  Secrets are supplied only at run time; this package never stores or logs
  them.
  """
  @callback fetch_secret(key :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Executes the call described by `descriptor` with the host's own
  authentication. The host resolves `:system`, `:company_id`, and
  `:connection_id` to its own allowlisted, stored connection — it never
  executes arbitrary URLs. Returns the decoded response or
  `{:error, reason}`.
  """
  @callback request(descriptor :: request_descriptor()) :: {:ok, map() | :ok} | {:error, term()}

  @doc """
  Appends `event` (a plain data map) to the host's audit log. The host is
  responsible for the reliability of its own log.
  """
  @callback audit(event :: map()) :: :ok | {:error, term()}

  @doc """
  Routes `request` to a human approver and returns `{:ok, ref}` with an
  opaque approval reference, or `{:error, reason}`. Agents must wait for the
  human decision before proceeding with the gated action.
  """
  @callback request_approval(request :: approval_request()) ::
              {:ok, approval_ref()} | {:error, term()}

  @doc """
  Sends `message` to `recipient` (a topic or user identifier the host
  resolves).
  """
  @callback notify(recipient :: String.t(), message :: String.t()) :: :ok | {:error, term()}
end
