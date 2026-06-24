defmodule DefdoTenantBoundary.CacheTest do
  use ExUnit.Case, async: true

  alias Defdo.Tenant
  alias Defdo.Tenant.Cache

  describe "key/1" do
    test "prefixes with tenant_id when context is set" do
      Tenant.with_tenant("tenant-abc", fn ->
        assert Cache.key("user:42") == "tenant-abc:user:42"
      end)
    end

    test "returns global: prefix in observe mode when no context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)
        assert Cache.key("user:1") == "global:user:1"
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when no context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        assert_raise ArgumentError, ~r/without tenant context/, fn ->
          Cache.key("user:1")
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

  describe "global_key/1" do
    test "returns global: prefix without needing context" do
      assert Cache.global_key("rate_limit:1.2.3.4") == "global:rate_limit:1.2.3.4"
    end
  end
end
