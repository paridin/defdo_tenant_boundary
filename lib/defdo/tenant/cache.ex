defmodule Defdo.Tenant.Cache do
  @moduledoc """
  Tenant-aware cache key builder.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  A shared cache (ETS, Redis, etc.) can leak data across tenants if keys
  are not namespaced. Prefix every key with the current tenant ID:

      key = Defdo.Tenant.Cache.key("user:42")
      # => "tenant-abc:user:42"

  Global keys (shared across tenants) use `global_key/1`:

      key = Defdo.Tenant.Cache.global_key("rate_limit:1.2.3.4")
      # => "global:rate_limit:1.2.3.4"

  ## Usage

      Defdo.Tenant.with_tenant("tenant-abc", fn ->
        key = Defdo.Tenant.Cache.key("user:42")
        Cachex.get(:my_cache, key)
      end)

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement:

  | Mode | Missing-context behaviour |
  |---|---|
  | `:observe` (default) | Emit telemetry; prefix with `"global:"` |
  | `:warn` | Telemetry + log warning; prefix with `"global:"` |
  | `:test_enforce` | Raise (test/CI only) |
  | `:strict` | Raise |

  ## See also

  * `Defdo.Tenant.Config` — enforcement modes
  * `Defdo.Tenant.Storage` — same pattern for object storage paths
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @doc """
  Build a tenant-scoped cache key.

  Prefixes `suffix` with the current tenant ID. When no tenant context is
  available, enforcement mode determines behaviour (observe/warn/raise).
  """
  @spec key(String.t()) :: String.t()
  def key(suffix) when is_binary(suffix) do
    case Context.tenant_id() do
      nil ->
        on_missing_context(suffix)
        "global:" <> suffix

      tenant_id when is_binary(tenant_id) ->
        tenant_id <> ":" <> suffix
    end
  end

  @doc """
  Build a global cache key (explicitly non-tenant-scoped).

  Prefixes `suffix` with `"global:"`. No tenant context required.
  """
  @spec global_key(String.t()) :: String.t()
  def global_key(suffix) when is_binary(suffix) do
    "global:" <> suffix
  end

  defp on_missing_context(suffix) do
    :telemetry.execute(
      [:defdo, :tenant, :cache, :key_missing_context],
      %{count: 1},
      %{suffix: suffix}
    )

    cond do
      Config.raising?() ->
        raise ArgumentError,
              "Defdo.Tenant.Cache.key/1 called without tenant context. " <>
                "Set a context with Defdo.Tenant.with_tenant/2 or use global_key/1."

      Config.warning?() ->
        require Logger
        Logger.warning("Cache.key/1 without tenant context — prefixing with global:")

      true ->
        :ok
    end
  end
end
