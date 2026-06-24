defmodule DefdoTenantBoundary.WorkerTest do
  use ExUnit.Case, async: true

  alias Defdo.Tenant
  alias Defdo.Tenant.Context
  alias Defdo.Tenant.Worker

  defmodule ScopedWorker do
    use Defdo.Tenant.Worker, queue: :default

    def perform_with_tenant(job) do
      send(:test_process, {:tenant_id, Tenant.current_tenant_id()})
      send(:test_process, {:job, job})
      :ok
    end
  end

  describe "restore_context_from_job/1" do
    test "restores context from job meta" do
      ctx = Context.new("tenant-789")

      job = %Oban.Job{
        worker: "TestWorker",
        meta: %{"defdo_tenant_context" => Context.to_serializable(ctx)}
      }

      Process.register(self(), :test_process)

      Worker.restore_context_from_job(job)

      assert Tenant.current_tenant_id() == "tenant-789"
    after
      Process.unregister(:test_process)
      Context.clear()
    end

    test "warns when meta has no context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        job = %Oban.Job{worker: "TestWorker", meta: %{}}

        result = Worker.restore_context_from_job(job)
        assert is_nil(result)
        assert is_nil(Tenant.current_tenant_id())
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when no context in meta" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        job = %Oban.Job{worker: "TestWorker", meta: %{}}

        assert_raise ArgumentError, ~r/no tenant context/, fn ->
          Worker.restore_context_from_job(job)
        end
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end
  end

  describe "perform/1 wrapper" do
    test "restores context before perform_with_tenant" do
      ctx = Context.new("tenant-wrapped")

      job = %Oban.Job{
        worker: "DefdoTenantBoundary.WorkerTest.ScopedWorker",
        meta: %{"defdo_tenant_context" => Context.to_serializable(ctx)},
        args: %{},
        queue: "default",
        attempt: 1,
        max_attempts: 3
      }

      Process.register(self(), :test_process)

      ScopedWorker.perform(job)

      assert_received {:tenant_id, "tenant-wrapped"}
    after
      Process.unregister(:test_process)
      Context.clear()
    end
  end
end
