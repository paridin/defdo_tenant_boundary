# Defdo.Tenant.Boundary

Cross-process tenant boundary wrappers — Oban, GenServer, PubSub, Webhook.

Part of the [Defdo Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

## Installation

```elixir
def deps do
  [
    {:defdo_tenant_boundary, "~> 0.1", organization: "defdo"}
  ]
end
```

## Included Wrappers

### Oban

```elixir
# Insert with tenant context auto-attached
{:ok, job} = Defdo.Tenant.Oban.insert(MyWorker, %{user_id: 42})
{:ok, job} = Defdo.Tenant.Oban.insert(MyWorker, %{user_id: 42}, queue: :critical)

# Build changeset (like Oban.Job.new/2)
changeset = Defdo.Tenant.Oban.new(%{user_id: 42}, worker: MyWorker)
```

### Worker

```elixir
defmodule MyApp.Workers.SyncTenant do
  use Defdo.Tenant.Worker, queue: :default, max_attempts: 3

  def perform_with_tenant(%Oban.Job{args: args}) do
    # tenant context is already restored here
    do_tenant_work(args)
  end
end
```

## Telemetry

All wrappers emit telemetry events following `Defdo.Tenant.Config` enforcement modes:

| Event | When |
|---|---|
| `[:defdo, :tenant, :oban, :context_captured]` | Context serialized into job meta |
| `[:defdo, :tenant, :oban, :context_missing]` | No tenant context at insertion |
| `[:defdo, :tenant, :context, :restored]` | Context restored from job meta |
| `[:defdo, :tenant, :context, :missing]` | No context in job meta at execution |

## License

Apache-2.0
