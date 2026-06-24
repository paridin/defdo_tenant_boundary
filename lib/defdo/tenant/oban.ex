defmodule Defdo.Tenant.Oban do
  @moduledoc """
  Tenant-safe Oban job insertion — part of the Tenant Boundary Kit.

  Oban jobs run in **separate processes** and do not inherit the caller's tenant
  context. This module captures the current `Defdo.Tenant.Context` and serializes
  it into the job's `meta` map so `Defdo.Tenant.Worker` can restore it before
  `perform/1` runs.

  ## Usage

      # Build a changeset (like Oban.Job.new/2):
      changeset = Defdo.Tenant.Oban.new(%{user_id: 42}, worker: MyWorker)

      # Insert a job directly:
      {:ok, job} = Defdo.Tenant.Oban.insert(MyWorker, %{user_id: 42})
      {:ok, job} = Defdo.Tenant.Oban.insert(MyWorker, %{user_id: 42}, queue: :critical)

  ## Telemetry

  Emits `[:defdo, :tenant, :oban, :context_captured]` when context is attached,
  and `[:defdo, :tenant, :oban, :context_missing]` when absent.
  Enforcement mirrors `Defdo.Tenant.Config` (observe/warn/raise).
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @context_meta_key "defdo_tenant_context"

  @doc """
  Build a job changeset with tenant context captured into `meta`.

  Returns an `Ecto.Changeset` ready for `Oban.insert/1`.
  """
  @spec new(map(), keyword()) :: Ecto.Changeset.t()
  def new(args, opts) when is_map(args) and is_list(opts) do
    args
    |> Oban.Job.new(opts)
    |> attach_tenant()
  end

  @doc """
  Insert a tenant-scoped job.

  Delegates to `Oban.Job.new/2`, attaches tenant context, and calls `Oban.insert/1`.
  """
  @spec insert(module(), map(), keyword()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def insert(worker, args, opts \\ []) when is_atom(worker) and is_map(args) and is_list(opts) do
    merged = Keyword.put(opts, :worker, worker) |> Keyword.put_new(:args, args)

    args
    |> Oban.Job.new(merged)
    |> attach_tenant()
    |> Oban.insert()
  end

  @doc """
  Attach tenant context to an existing changeset or job struct.
  Useful when wrapping jobs built by other libraries.
  """
  def attach_tenant(%Ecto.Changeset{data: %Oban.Job{} = job} = cs) do
    %{cs | data: put_meta(job)}
  end

  def attach_tenant(%Oban.Job{} = job) do
    put_meta(job)
  end

  # ── Internals ─────────────────────────────────────────────────────────────────

  defp put_meta(%Oban.Job{} = job) do
    case Context.capture() do
      %Context{} = ctx ->
        :telemetry.execute(
          [:defdo, :tenant, :oban, :context_captured],
          %{count: 1},
          %{worker: job.worker, scope: ctx.scope}
        )

        meta = Map.put(job.meta, @context_meta_key, Context.to_serializable(ctx))
        %Oban.Job{job | meta: meta}

      nil ->
        :telemetry.execute(
          [:defdo, :tenant, :oban, :context_missing],
          %{count: 1},
          %{worker: job.worker}
        )

        cond do
          Config.raising?() ->
            raise ArgumentError,
                  "Defdo.Tenant.Oban job #{inspect(job.worker)} has no tenant context. " <>
                    "Set a context with Defdo.Tenant.with_tenant/2 or use a global/system-edge context."

          Config.warning?() ->
            require Logger
            Logger.warning("Defdo.Tenant.Oban job #{inspect(job.worker)} has no tenant context")

          true ->
            :ok
        end

        job
    end
  end
end
