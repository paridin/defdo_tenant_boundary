defmodule Defdo.Tenant.GenServer do
  @moduledoc """
  Tenant-context carrying GenServer helpers.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  A GenServer runs in its **own process** — callbacks do not inherit tenant context
  from callers. Use the helpers below to capture context at init and restore it
  before every callback.

  ## Usage

      defmodule MyApp.TenantCache do
        use GenServer

        def start_link(tenant_id) do
          GenServer.start_link(__MODULE__, tenant_id)
        end

        @impl true
        def init(tenant_id) do
          Defdo.Tenant.GenServer.capture_init_context()
          {:ok, %{cache: %{}}}
        end

        @impl true
        def handle_call({:get, key}, _from, state) do
          Defdo.Tenant.GenServer.restore_context()
          {:reply, Map.get(state.cache, key), state}
        end

        @impl true
        def handle_cast({:put, key, value}, state) do
          Defdo.Tenant.GenServer.restore_context()
          {:noreply, Map.put(state, :cache, Map.put(state.cache, key, value))}
        end
      end

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement:

  | Mode | Missing-context behaviour |
  |---|---|
  | `:observe` (default) | Emit telemetry; continue |
  | `:warn` | Telemetry + log warning |
  | `:test_enforce` | Raise (test/CI only) |
  | `:strict` | Raise |

  ## Telemetry

  | Event | Metadata |
  |---|---|
  | `[:defdo, :tenant, :genserver, :context_captured]` | `module`, `scope` |
  | `[:defdo, :tenant, :genserver, :context_missing]` | `module` |
  | `[:defdo, :tenant, :context, :restored]` | `boundary: :genserver`, `module`, `scope` |

  ## See also

  * `Defdo.Tenant.Context` — process-local context storage
  * `Defdo.Tenant.Config` — enforcement modes
  * `Defdo.Tenant.Worker` — automatic wrapping via `use` macro (Oban)
  * `Defdo.Tenant.Boundary.Task` — automatic wrapping for `Task.async`
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @genserver_context_key :defdo_tenant_genserver_context

  @doc """
  Capture the calling process's tenant context for the GenServer process.

  Call at the start of `c:GenServer.init/1`. Stores a serialized copy
  in the process dictionary so `restore_context/0` can rehydrate it
  in every callback.
  """
  @spec capture_init_context() :: Context.t() | nil
  def capture_init_context do
    case Context.capture() do
      %Context{} = ctx ->
        :telemetry.execute(
          [:defdo, :tenant, :genserver, :context_captured],
          %{count: 1},
          %{module: nil, scope: ctx.scope}
        )

        Process.put(@genserver_context_key, Context.to_serializable(ctx))
        ctx

      nil ->
        :telemetry.execute(
          [:defdo, :tenant, :genserver, :context_missing],
          %{count: 1},
          %{module: nil}
        )

        cond do
          Config.raising?() ->
            raise ArgumentError,
                  "GenServer init has no tenant context. " <>
                    "Set a context before start_link or pass it as an init arg."

          Config.warning?() ->
            require Logger
            Logger.warning("GenServer init has no tenant context")

          true ->
            :ok
        end

        nil
    end
  end

  @doc """
  Restore the captured context before executing callback logic.

  Call at the top of every `c:GenServer.handle_call/3`,
  `c:GenServer.handle_cast/2`, and `c:GenServer.handle_info/2`.

  Returns the restored `%Defdo.Tenant.Context{}` or `nil`.
  """
  @spec restore_context() :: Context.t() | nil
  def restore_context do
    Context.clear()

    case Process.get(@genserver_context_key) do
      map when is_map(map) and map_size(map) > 0 ->
        ctx = Context.from_serializable(map)
        Context.put(ctx)

        :telemetry.execute(
          [:defdo, :tenant, :context, :restored],
          %{count: 1},
          %{boundary: :genserver, scope: ctx.scope}
        )

        ctx

      _ ->
        :telemetry.execute(
          [:defdo, :tenant, :context, :missing],
          %{count: 1},
          %{boundary: :genserver}
        )

        cond do
          Config.raising?() ->
            raise ArgumentError,
                  "GenServer callback has no tenant context. " <>
                    "Call capture_init_context/0 in init/1."

          Config.warning?() ->
            require Logger
            Logger.warning("GenServer callback has no tenant context")

          true ->
            :ok
        end

        nil
    end
  end
end
