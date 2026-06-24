defmodule DefdoTenantBoundary.WebhookTest do
  use ExUnit.Case, async: false

  alias Defdo.Tenant
  alias Defdo.Tenant.Webhook

  defmodule TestResolver do
    def by_client_id(%{client_id: "known-client"}), do: profile()
    def by_client_id(_), do: nil

    defp profile do
      %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-resolved-456",
        domain: "known.example.com",
        is_active: true
      }
    end
  end

  describe "resolve/2 with custom resolver" do
    test "resolves tenant using custom MFA" do
      result = Webhook.resolve(
        %{client_id: "known-client"},
        resolver: {TestResolver, :by_client_id, []}
      )

      assert {:ok, profile} = result
      assert profile.tenant_id == "tenant-resolved-456"
    end

    test "returns unresolved when custom resolver returns nil" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :observe)

        result = Webhook.resolve(
          %{client_id: "unknown"},
          resolver: {TestResolver, :by_client_id, []}
        )

        assert {:error, :unresolved} = result
      after
        if original do
          Application.put_env(:defdo_tenant, :enforcement, original)
        else
          Application.delete_env(:defdo_tenant, :enforcement)
        end
      end
    end

    test "raises in strict mode when unresolved" do
      original = Application.get_env(:defdo_tenant, :enforcement, :observe)

      try do
        Application.put_env(:defdo_tenant, :enforcement, :strict)

        assert_raise ArgumentError, ~r/unable to resolve/, fn ->
          Webhook.resolve(
            %{client_id: "unknown"},
            resolver: {TestResolver, :by_client_id, []}
          )
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

  describe "resolve/2 with built-in resolvers" do
    test "raises for unknown resolver type" do
      assert_raise ArgumentError, ~r/unknown webhook resolver/, fn ->
        Webhook.resolve(%{host: "x.com"}, resolver: :unknown_resolver)
      end
    end
  end

  describe "execute/2" do
    test "executes function in tenant context" do
      profile = %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-exec-789",
        domain: "example.com",
        is_active: true
      }

      caller = self()

      Webhook.execute(profile, fn ->
        assert Tenant.current_tenant_id() == "tenant-exec-789"
        send(caller, {:executed, Tenant.current_tenant_id()})
      end)

      assert_received {:executed, "tenant-exec-789"}
      assert is_nil(Tenant.current_tenant_id())
    end

    test "clears context even on exception" do
      profile = %Defdo.Tenant.Schema.Profile{
        tenant_id: "tenant-exec-err",
        domain: "example.com",
        is_active: true
      }

      catch_error(
        Webhook.execute(profile, fn ->
          raise "boom"
        end)
      )

      assert is_nil(Tenant.current_tenant_id())
    end
  end
end
