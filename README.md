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

## Wrappers

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
    # tenant context already restored here
    do_tenant_work(args)
  end
end
```

### GenServer

```elixir
defmodule MyApp.TenantCache do
  use GenServer

  def start_link(tenant_id) do
    GenServer.start_link(__MODULE__, tenant_id)
  end

  @impl true
  def init(tenant_id) do
    Defdo.Tenant.GenServer.capture_init_context()
    {:ok, %{}}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    Defdo.Tenant.GenServer.restore_context()
    {:reply, state, state}
  end
end
```

## Enforcement Modes

All wrappers respect `Defdo.Tenant.Config` enforcement modes:

| Mode | Missing-context behaviour |
|---|---|
| `:observe` (default) | Emit telemetry; continue |
| `:warn` | Telemetry + log warning |
| `:test_enforce` | Raise (test/CI only) |
| `:strict` | Raise |

## Telemetry

| Event | Source | Metadata |
|---|---|---|
| `[:defdo, :tenant, :oban, :context_captured]` | Oban | `worker`, `scope` |
| `[:defdo, :tenant, :oban, :context_missing]` | Oban | `worker` |
| `[:defdo, :tenant, :genserver, :context_captured]` | GenServer | `scope` |
| `[:defdo, :tenant, :genserver, :context_missing]` | GenServer | `module` |
| `[:defdo, :tenant, :context, :restored]` | Worker, GenServer | `boundary`, `worker`/`module`, `scope` |
| `[:defdo, :tenant, :context, :missing]` | Worker, GenServer | `boundary`, `worker`/`module` |

## License

Apache-2.0
