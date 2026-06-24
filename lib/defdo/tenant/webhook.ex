defmodule Defdo.Tenant.Webhook do
  @moduledoc """
  Tenant-safe webhook processing — two-phase trusted-edge resolution.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  ## Problem

  Webhooks arrive from external providers with no authenticated session and no
  tenant context. The webhook payload may contain a tenant identifier, but
  **untrusted request bodies must never be used directly for tenant resolution**.

  ## Solution — two-phase pattern

  1. **Trusted-edge resolution** — identify the tenant from trusted data
     (host, route, credential fingerprint, webhook secret ref, client ID,
     provider account ref). Queries use audited `skip_tenant_id`.
  2. **Tenant execution** — restore context and run business logic scoped
     to the resolved tenant.

  ## Usage

      # Phase 1: resolve tenant from trusted edge data
      tenant = Defdo.Tenant.Webhook.resolve(
        %{host: "my-tenant.example.com"},
        resolver: :host
      )

      # Phase 2: execute business logic in tenant context
      Defdo.Tenant.Webhook.execute(tenant, fn ->
        # Repo queries are scoped to the resolved tenant
        process_webhook_payload(payload)
      end)

  ## Built-in resolvers

  | Resolver | Trusted data | Query |
  |---|---|---|
  | `:host` | `%{host: "..."}` | Matches `Profile.domain` or `allowed_domains` |
  | `:domain` | `%{domain: "..."}` | Matches `Profile.domain` |
  | `{module, function, args}` | Custom | User-defined MFA returning `%Profile{}` or `nil` |

  Custom resolver example:

      resolver = {MyApp.Resolver, :by_client_id, []}

      Defdo.Tenant.Webhook.resolve(
        %{client_id: "stripe-acc-123"},
        resolver: resolver
      )

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement:

  | Mode | Unresolved tenant behaviour |
  |---|---|
  | `:observe` (default) | Return `nil` + emit telemetry |
  | `:warn` | Telemetry + log warning; return `nil` |
  | `:test_enforce` | Raise (test/CI only) |
  | `:strict` | Raise |

  ## Telemetry

  | Event | Metadata |
  |---|---|
  | `[:defdo, :tenant, :webhook, :resolved]` | `resolver`, `tenant_id` |
  | `[:defdo, :tenant, :webhook, :unresolved]` | `resolver` |
  | `[:defdo, :tenant, :context, :restored]` | `boundary: :webhook`, `scope` |

  ## See also

  * `Defdo.Tenant.Config` — enforcement modes + repo configuration
  * `Defdo.Tenant.Repo.Protection` — audited `skip_tenant_id` used by resolvers
  * `Defdo.Tenant.AllowedOrigin` — similar pattern for Phoenix `check_origin`
  """

  require Logger
  import Ecto.Query, only: [from: 2]

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context
  alias Defdo.Tenant.Schema.Profile

  @typedoc """
  Tenant resolution result: `{:ok, %Profile{}}` or `{:error, reason}`.
  """
  @type resolve_result :: {:ok, Profile.t()} | {:error, :unresolved | term()}

  @doc """
  Resolve a tenant from trusted webhook data using a configured resolver.

  ## Parameters

    * `trusted_data` — map of trusted edge data (host, domain, credential, etc.)
    * `opts`:
      * `:resolver` — `:host`, `:domain`, or `{Module, :function, [extra_args]}`
      * `:repo` — override the configured repo (default: `Config.repo/0`)

  ## Returns

    * `{:ok, %Profile{}}` — tenant found
    * `{:error, :unresolved}` — no tenant matched (or context not available)
    * `{:error, reason}` — repository error

  ## Examples

      # Resolve by host (domain + allowed_domains + free_fqdn)
      Defdo.Tenant.Webhook.resolve(%{host: "acme.example.com"}, resolver: :host)

      # Resolve by domain only
      Defdo.Tenant.Webhook.resolve(%{domain: "acme.example.com"}, resolver: :domain)

      # Custom resolver
      Defdo.Tenant.Webhook.resolve(
        %{credential_id: "key-123"},
        resolver: {MyApp.Resolver, :by_credential, []}
      )
  """
  @spec resolve(map(), keyword()) :: resolve_result()
  def resolve(trusted_data, opts \\ []) when is_map(trusted_data) and is_list(opts) do
    repo = Keyword.get(opts, :repo) || Config.repo()
    resolver = Keyword.get(opts, :resolver)

    resolve_tenant(repo, resolver, trusted_data)
  end

  @doc """
  Execute business logic in a resolved tenant's context.

  Sets the tenant context from the profile's `tenant_id`, runs `fun`,
  and clears context afterwards (even on exception).

  ## Example

      case Defdo.Tenant.Webhook.resolve(payload, resolver: :host) do
        {:ok, tenant} ->
          Defdo.Tenant.Webhook.execute(tenant, fn ->
            process_webhook(payload)
          end)

        {:error, _reason} ->
          Logger.warning("Webhook tenant unresolved")
      end
  """
  @spec execute(Profile.t(), (-> any())) :: any()
  def execute(%Profile{tenant_id: tenant_id}, fun) when is_function(fun, 0) do
    Context.clear()
    Context.put(Context.new(tenant_id))

    :telemetry.execute(
      [:defdo, :tenant, :context, :restored],
      %{count: 1},
      %{boundary: :webhook, scope: :tenant}
    )

    fun.()
  rescue
    e -> reraise e, __STACKTRACE__
  after
    Context.clear()
  end

  # ── Resolvers ─────────────────────────────────────────────────────────────────

  defp resolve_tenant(nil, :host, _data) do
    raise_missing_repo()
  end

  defp resolve_tenant(nil, :domain, _data) do
    raise_missing_repo()
  end

  defp resolve_tenant(repo, resolver, trusted_data) do
    result = run_resolver(repo, resolver, trusted_data)
    handle_resolution(result, resolver)
  end

  defp run_resolver(repo, :host, trusted_data) do
    ensure_repo!(repo)
    resolve_by_host(repo, trusted_data)
  end

  defp run_resolver(repo, :domain, trusted_data) do
    ensure_repo!(repo)
    resolve_by_domain(repo, trusted_data)
  end

  defp run_resolver(_repo, {module, function, args}, trusted_data)
       when is_atom(module) and is_atom(function) and is_list(args) do
    apply(module, function, [trusted_data | args])
  end

  defp run_resolver(_repo, nil, _trusted_data), do: nil

  defp run_resolver(_repo, resolver, _trusted_data) do
    raise ArgumentError,
          "unknown webhook resolver #{inspect(resolver)}. " <>
            "Valid resolvers: :host, :domain, or {Module, :function, [args]}"
  end

  defp handle_resolution(%Profile{} = profile, resolver) do
    :telemetry.execute(
      [:defdo, :tenant, :webhook, :resolved],
      %{count: 1},
      %{resolver: resolver, tenant_id: profile.tenant_id}
    )

    {:ok, profile}
  end

  defp handle_resolution(nil, resolver) do
    :telemetry.execute(
      [:defdo, :tenant, :webhook, :unresolved],
      %{count: 1},
      %{resolver: resolver}
    )

    cond do
      Config.raising?() ->
        raise ArgumentError,
              "Defdo.Tenant.Webhook: unable to resolve tenant using resolver #{inspect(resolver)}"

      Config.warning?() ->
        Logger.warning(
          "Defdo.Tenant.Webhook: unable to resolve tenant using resolver #{inspect(resolver)}"
        )

      true ->
        :ok
    end

    {:error, :unresolved}
  end

  defp handle_resolution({:error, reason}, _resolver), do: {:error, reason}

  # ── Built-in resolvers ────────────────────────────────────────────────────────

  defp resolve_by_host(repo, %{host: host}) when is_binary(host) and host != "" do
    normalized = String.downcase(host)

    profile =
      from(p in Profile,
        where: p.is_active == true,
        where:
          p.domain == ^normalized or
            fragment("? = ANY(?)", ^normalized, p.allowed_domains) or
            p.free_fqdn == ^normalized
      )
      |> repo.one(skip_tenant_id: [reason: "webhook: trusted-edge tenant resolution by host"])

    profile
  end

  defp resolve_by_host(_repo, _data), do: nil

  defp resolve_by_domain(repo, %{domain: domain}) when is_binary(domain) and domain != "" do
    normalized = String.downcase(domain)

    profile =
      from(p in Profile,
        where: p.is_active == true,
        where: p.domain == ^normalized
      )
      |> repo.one(skip_tenant_id: [reason: "webhook: trusted-edge tenant resolution by domain"])

    profile
  end

  defp resolve_by_domain(_repo, _data), do: nil

  defp ensure_repo!(nil), do: raise_missing_repo()
  defp ensure_repo!(_repo), do: :ok

  defp raise_missing_repo do
    raise ArgumentError,
          "Defdo.Tenant.Webhook: no repo configured. " <>
            "Set `config :defdo_tenant, repo: MyApp.Repo`."
  end
end
