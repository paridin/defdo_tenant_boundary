defmodule DefdoTenantBoundary.ObanTest do
  use ExUnit.Case, async: true

  alias Defdo.Tenant.Context

  defmodule Support.Worker do
    use Oban.Worker, queue: :default

    @impl true
    def perform(_job), do: :ok
  end

  alias Support.Worker, as: TestWorker

  describe "new/2" do
    test "attaches tenant context to job meta" do
      Context.put(Context.new("tenant-123"))

      cs = Defdo.Tenant.Oban.new(%{user_id: 1}, worker: TestWorker)

      assert %Ecto.Changeset{data: %Oban.Job{} = job} = cs
      assert %{"defdo_tenant_context" => ctx} = job.meta
      assert ctx["tenant_id"] == "tenant-123"
      assert ctx["scope"] == "tenant"
    after
      Context.clear()
    end

    test "warns when no tenant context is set" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        cs = Defdo.Tenant.Oban.new(%{user_id: 1}, worker: TestWorker)

        assert %Ecto.Changeset{data: %Oban.Job{} = job} = cs
        refute Map.has_key?(job.meta, "defdo_tenant_context")
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when no tenant context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        assert_raise ArgumentError, ~r/no tenant context/, fn ->
          Defdo.Tenant.Oban.new(%{user_id: 1}, worker: TestWorker)
        end
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "attaches tenant context with custom queue" do
      Context.put(Context.new("tenant-456"))

      cs = Defdo.Tenant.Oban.new(%{user_id: 2}, worker: TestWorker, priority: 1)

      assert %Ecto.Changeset{data: %Oban.Job{} = job} = cs
      assert %{"defdo_tenant_context" => ctx} = job.meta
      assert ctx["tenant_id"] == "tenant-456"
    after
      Context.clear()
    end
  end
end
