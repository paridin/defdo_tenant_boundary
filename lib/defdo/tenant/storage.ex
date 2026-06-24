defmodule Defdo.Tenant.Storage do
  @moduledoc """
  Tenant-aware object storage path builder.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  ## Problem

  Object storage (S3, GCS, etc.) with a flat key structure can leak files
  across tenants. A path like `"uploads/avatar.jpg"` from tenant A would
  collide with tenant B's `"uploads/avatar.jpg"`.

  ## Solution

  `Defdo.Tenant.Storage.path/2` prefixes every path with the tenant ID:

      Defdo.Tenant.Storage.path("uploads/avatar.jpg")
      # => "tenants/tenant-123/uploads/avatar.jpg"

  Global paths use `global_path/1`:

      Defdo.Tenant.Storage.global_path("public/logo.png")
      # => "global/public/logo.png"

  In `:strict` mode, `path/2` raises when no tenant context is set.

  ## Usage

      # In a tenant-scoped context:
      Defdo.Tenant.with_tenant("tenant-abc", fn ->
        path = Defdo.Tenant.Storage.path("uploads/avatar.jpg")
        # path == "tenants/tenant-abc/uploads/avatar.jpg"
        S3.put_object(bucket, path, file)
      end)

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement:

  | Mode | Missing-context behaviour |
  |---|---|
  | `:observe` (default) | Emit telemetry; prefix with `"global/"` |
  | `:warn` | Telemetry + log warning; prefix with `"global/"` |
  | `:test_enforce` | Raise (test/CI only) |
  | `:strict` | Raise |

  ## Telemetry

  | Event | Metadata |
  |---|---|
  | `[:defdo, :tenant, :storage, :path_missing_context]` | `suffix` |

  ## See also

  * `Defdo.Tenant.Config` — enforcement modes
  * `Defdo.Tenant.Cache` — same pattern for cache keys
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @doc """
  Build a tenant-scoped storage path.

  Prefixes `suffix` with `"tenants/:tenant_id/"`. When no tenant context
  is available, enforcement mode determines behaviour.

  ## Examples

      Defdo.Tenant.with_tenant("t-1", fn ->
        path = Defdo.Tenant.Storage.path("uploads/avatar.jpg")
        # path == "tenants/t-1/uploads/avatar.jpg"
      end)
  """
  @spec path(String.t()) :: String.t()
  def path(suffix) when is_binary(suffix) do
    case Context.tenant_id() do
      nil ->
        on_missing_context(suffix)
        "global/" <> suffix

      tenant_id when is_binary(tenant_id) ->
        "tenants/" <> tenant_id <> "/" <> suffix
    end
  end

  @doc """
  Build a global storage path (explicitly non-tenant-scoped).

  Prefixes `suffix` with `"global/"`. No tenant context required.
  """
  @spec global_path(String.t()) :: String.t()
  def global_path(suffix) when is_binary(suffix) do
    "global/" <> suffix
  end

  # ── Internals ─────────────────────────────────────────────────────────────────

  defp on_missing_context(suffix) do
    :telemetry.execute(
      [:defdo, :tenant, :storage, :path_missing_context],
      %{count: 1},
      %{suffix: suffix}
    )

    cond do
      Config.raising?() ->
        raise ArgumentError,
              "Defdo.Tenant.Storage.path/1 called without tenant context. " <>
                "Set a context with Defdo.Tenant.with_tenant/2 or use global_path/1."

      Config.warning?() ->
        require Logger

        Logger.warning(
          "Defdo.Tenant.Storage.path/1 called without tenant context — prefixing with global/"
        )

      true ->
        :ok
    end
  end
end
