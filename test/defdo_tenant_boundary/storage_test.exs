defmodule DefdoTenantBoundary.StorageTest do
  use ExUnit.Case, async: true

  alias Defdo.Tenant
  alias Defdo.Tenant.Storage

  describe "path/1" do
    test "prefixes with tenants/:tenant_id when context is set" do
      Tenant.with_tenant("tenant-xyz", fn ->
        assert Storage.path("uploads/avatar.jpg") == "tenants/tenant-xyz/uploads/avatar.jpg"
      end)
    end

    test "returns global/ prefix in observe mode when no context" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)
        assert Storage.path("uploads/file.txt") == "global/uploads/file.txt"
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
          Storage.path("uploads/file.txt")
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

  describe "global_path/1" do
    test "returns global/ prefix without needing context" do
      assert Storage.global_path("public/logo.png") == "global/public/logo.png"
    end
  end
end
