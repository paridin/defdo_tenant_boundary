defmodule DefdoTenantBoundary.GenServerTest do
  use ExUnit.Case, async: false

  alias Defdo.Tenant
  alias Defdo.Tenant.Context
  alias Defdo.Tenant.GenServer, as: TGS

  defmodule TenantCache do
    use GenServer

    def start_link(tenant_id) do
      Context.put(Context.new(tenant_id))
      GenServer.start_link(__MODULE__, tenant_id)
    after
      Context.clear()
    end

    @impl true
    def init(tenant_id) do
      Context.put(Context.new(tenant_id))
      TGS.capture_init_context()
      {:ok, %{tenant_id: tenant_id, cache: %{}}}
    after
      Context.clear()
    end

    @impl true
    def handle_call({:put, key, value}, _from, state) do
      TGS.restore_context()
      current_tid = Tenant.current_tenant_id()
      cache = Map.put(state.cache, key, value)
      {:reply, {:ok, current_tid}, %{state | cache: cache}}
    end

    @impl true
    def handle_cast({:put_async, key, value}, state) do
      TGS.restore_context()
      current_tid = Tenant.current_tenant_id()
      send(:test_process, {:cast_tid, current_tid})
      cache = Map.put(state.cache, key, value)
      {:noreply, %{state | cache: cache}}
    end

    @impl true
    def handle_info({:get, _key}, state) do
      TGS.restore_context()
      current_tid = Tenant.current_tenant_id()
      send(:test_process, {:info_tid, current_tid})
      {:noreply, state}
    end
  end

  setup do
    Process.register(self(), :test_process)
    :ok
  end

  describe "init captures context" do
    test "restores tenant context in handle_call" do
      {:ok, pid} = TenantCache.start_link("tenant-gs-123")

      {:ok, tid} = GenServer.call(pid, {:put, :a, 1})

      assert tid == "tenant-gs-123"
    end

    test "restores tenant context in handle_cast" do
      {:ok, pid} = TenantCache.start_link("tenant-gs-456")

      GenServer.cast(pid, {:put_async, :b, 2})
      # flush the cast by making a sync call
      GenServer.call(pid, {:put, :flush, 0})

      assert_received {:cast_tid, "tenant-gs-456"}
    end

    test "restores tenant context in handle_info" do
      {:ok, pid} = TenantCache.start_link("tenant-gs-789")

      send(pid, {:get, :a})
      # flush async message by making a sync call
      GenServer.call(pid, {:put, :flush, 0})

      assert_received {:info_tid, "tenant-gs-789"}
    end

    test "does not leak context after callback" do
      {:ok, pid} = TenantCache.start_link("tenant-gs-no-leak")

      GenServer.call(pid, {:put, :x, 1})

      assert is_nil(Tenant.current_tenant_id())
    end
  end

  describe "capture_init_context enforcement" do
    test "raises in strict mode when no context at init" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        assert_raise ArgumentError, ~r/no tenant context/, fn ->
          TGS.capture_init_context()
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
end
