defmodule Defdo.Tenant.Worker do
  @moduledoc """
  Tenant-safe Oban worker behaviour.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  ## Usage

  Replace `use Oban.Worker` with `use Defdo.Tenant.Worker` and implement
  `perform_with_tenant/1` instead of `perform/1`:

      defmodule MyApp.Workers.SyncTenant do
        use Defdo.Tenant.Worker, queue: :default, max_attempts: 3

        def perform_with_tenant(%Oban.Job{args: args}) do
          # tenant context is already restored here
          do_tenant_work(args)
        end
      end

  ## How it works

  1. The `__using__` macro generates `perform/1` (the Oban callback).
  2. Before your `perform_with_tenant/1` runs, context is restored from
     `job.meta["defdo_tenant_context"]` via `restore_context_from_job/1`.
  3. After the callback returns (even on exception), context is cleared.
  4. Jobs inserted via `Defdo.Tenant.Oban.insert/3` or `Defdo.Tenant.Oban.new/2`
     automatically carry context in `meta`.

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement for missing context:

  | Mode | Missing-context behaviour |
  |---|---|
  | `:observe` (default) | Emit telemetry; continue without context |
  | `:warn` | Telemetry + log warning; continue |
  | `:test_enforce` | Raise (test/CI only) |
  | `:strict` | Raise |

  ## Telemetry

  | Event | Metadata |
  |---|---|
  | `[:defdo, :tenant, :context, :restored]` | `boundary: :oban`, `worker`, `scope` |
  | `[:defdo, :tenant, :context, :missing]` | `boundary: :oban`, `worker` |

  ## Standalone helper

  `restore_context_from_job/1` is public — call it directly when wrapping
  existing workers without adopting the macro:

      def perform(job) do
        Defdo.Tenant.Worker.restore_context_from_job(job)
        do_work(job)
      end

  ## See also

  * `Defdo.Tenant.Oban` — captures context at insertion time
  * `Defdo.Tenant.Config` — enforcement modes
  * `Defdo.Tenant.Boundary.Task` — same pattern for `Task.async`
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @context_meta_key "defdo_tenant_context"

  defmacro __using__(opts) do
    quote do
      use Oban.Worker, unquote(opts)

      @impl true
      def perform(job) do
        Defdo.Tenant.Worker.restore_context_from_job(job)
        perform_with_tenant(job)
      rescue
        e -> reraise e, __STACKTRACE__
      after
        Defdo.Tenant.Context.clear()
      end

      defoverridable perform: 1

      def perform_with_tenant(_job), do: :ok
      defoverridable perform_with_tenant: 1
    end
  end

  @doc """
  Restore tenant context from an Oban job's `meta` map.

  Called automatically by the generated `perform/1`. Also available as a
  standalone helper when wrapping existing workers without the macro.

  Returns the restored `%Defdo.Tenant.Context{}` or `nil`.
  """
  @spec restore_context_from_job(Oban.Job.t()) :: Context.t() | nil
  def restore_context_from_job(%Oban.Job{meta: meta, worker: worker}) do
    Context.clear()

    case Map.get(meta, @context_meta_key) do
      map when is_map(map) and map_size(map) > 0 ->
        ctx = Context.from_serializable(map)
        Context.put(ctx)

        :telemetry.execute(
          [:defdo, :tenant, :context, :restored],
          %{count: 1},
          %{boundary: :oban, worker: worker, scope: ctx.scope}
        )

        ctx

      _ ->
        :telemetry.execute(
          [:defdo, :tenant, :context, :missing],
          %{count: 1},
          %{boundary: :oban, worker: worker}
        )

        cond do
          Config.raising?() ->
            raise ArgumentError,
                  "Oban job #{inspect(worker)} has no tenant context in meta. " <>
                    "Use Defdo.Tenant.Oban.new/2 or Defdo.Tenant.Oban.insert/2 to attach context."

          Config.warning?() ->
            require Logger
            Logger.warning("Oban job #{inspect(worker)} has no tenant context in meta")

          true ->
            :ok
        end

        nil
    end
  end
end
