defmodule Defdo.Tenant.Boundary do
  @moduledoc """
  Cross-process tenant boundary wrappers for the Defdo ecosystem.

  `defdo_tenant_boundary` is the third layer of the Defdo Tenant Platform Kit:

  | Layer | Package | Purpose |
  |---|---|---|
  | Core | `defdo_tenant` | Process-local context, Repo scoping, Config |
  | Edge | `defdo_tenant_plug` | HTTP/Socket tenant resolution |
  | **Boundary** | `defdo_tenant_boundary` | Oban, GenServer, PubSub, Webhook wrappers |

  ## Included wrappers

    * `Defdo.Tenant.Oban` — tenant-safe job insertion (captures context into job meta)
    * `Defdo.Tenant.Worker` — tenant-safe worker behaviour (restores context before `perform_with_tenant/1`)

  ## Coming next

    * `Defdo.Tenant.GenServer` — tenant-context carrying GenServer
    * `Defdo.Tenant.PubSub` — tenant-aware PubSub envelope
    * `Defdo.Tenant.Webhook` — two-phase trusted-edge → tenant-runtime
    * `Defdo.Tenant.Cache` — tenant-aware cache key builders
    * `Defdo.Tenant.Storage` — tenant-aware object storage path builders

  ## Enforcement modes

  All wrappers respect `Defdo.Tenant.Config` enforcement modes (`:observe`,
  `:warn`, `:test_enforce`, `:strict`) and emit telemetry on context capture,
  restore, and missing events.
  """
end
