defmodule OpSkills.Tool do
  @moduledoc """
  Contract every tool in this pack implements.

  Tools are the only units that act on the outside world, and even they act
  through the `OpSkills.Host` — they never hold secrets or open connections.
  `run/2` receives the host module as its second argument.

  The host uses `name/0` to gate calls from the manifest's `allowed_tools`,
  and `risk/0` / `requires_approval?/0` to decide whether a human must
  approve before the tool runs.
  """

  @type risk :: :read | :write | :destructive
  @type result :: {:ok, map()} | {:error, term()}

  @doc "Unique tool name, as referenced by manifests (`allowed_tools`)."
  @callback name() :: String.t()

  @doc "One-line description of what the tool does."
  @callback description() :: String.t()

  @doc "Risk class: `:read` never mutates, `:write` mutates host-visible state, `:destructive` is irreversible."
  @callback risk() :: risk()

  @doc "Whether a human must approve before this tool runs."
  @callback requires_approval?() :: boolean()

  @doc "JSON-schema-style map describing the `run/2` arguments."
  @callback schema() :: map()

  @doc """
  Runs the tool with `args` and the `host` module. Returns `{:ok, result}`
  or `{:error, reason}`; a tool that ran successfully but found problems
  still returns `{:ok, result}` with the status inside the result.
  """
  @callback run(args :: map(), host :: module()) :: result()
end
