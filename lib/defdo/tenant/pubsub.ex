defmodule Defdo.Tenant.PubSub do
  @moduledoc """
  Tenant-aware PubSub envelope.

  Part of the [Tenant Boundary Platform Kit](https://github.com/defdo-dev/defdo_tenant/blob/main/docs/tenant-boundary-kit.md).

  ## Problem

  PubSub subscribers run in **separate processes** with no tenant context.
  A broadcast from tenant A arrives at a subscriber that must process it
  within tenant A's scope — but the subscriber has no context.

  ## Solution

  `Defdo.Tenant.PubSub` wraps every outgoing message in a tenant-aware envelope
  that carries the serialized `Defdo.Tenant.Context`. Subscribers unwrap the
  envelope with `handle_message/2`, which restores context before the callback.

  ## Envelope format

      %{
        "event" => "order:created",
        "payload" => %{order_id: 123},
        "tenant_context" => %{
          "tenant_id" => "tenant-uuid",
          "scope" => "tenant",
          "slug" => nil,
          "meta" => %{"correlation_id" => "abc"}
        },
        "published_at" => 1719000000
      }

  ## Usage — broadcast

      # Phoenix.PubSub
      Defdo.Tenant.PubSub.broadcast(
        MyApp.PubSub, "tenant:orders", "order:created", %{order_id: 123}
      )

      # Without topic:
      Defdo.Tenant.PubSub.broadcast(
        MyApp.PubSub, "tenant:orders", :order_created, %{order_id: 123}
      )

  ## Usage — subscribe

      # In your subscriber GenServer:
      def init(_) do
        Defdo.Tenant.PubSub.subscribe(MyApp.PubSub, "tenant:orders")
        {:ok, %{}}
      end

      def handle_info({:tenant_event, envelope}, state) do
        Defdo.Tenant.PubSub.handle_message(envelope, fn payload ->
          # tenant context restored — Repo queries scoped
          process_order(payload)
        end)

        {:noreply, state}
      end

  ## Enforcement modes

  Respects `Defdo.Tenant.Config` enforcement:

  | Mode | Missing-context behaviour |
  |---|---|
  | `:observe` (default) | Emit telemetry; broadcast without context |
  | `:warn` | Telemetry + log warning; broadcast anyway |
  | `:test_enforce` | Raise (test/CI only) |
  | `:strict` | Raise |

  ## Telemetry

  | Event | Metadata |
  |---|---|
  | `[:defdo, :tenant, :pubsub, :published]` | `event`, `topic`, `scope` |
  | `[:defdo, :tenant, :pubsub, :context_missing]` | `event`, `topic` |
  | `[:defdo, :tenant, :context, :restored]` | `boundary: :pubsub`, `event`, `scope` |

  ## See also

  * `Defdo.Tenant.Context` — process-local context storage
  * `Defdo.Tenant.Config` — enforcement modes
  * `Defdo.Tenant.Worker` — same pattern for Oban workers
  """

  alias Defdo.Tenant.Config
  alias Defdo.Tenant.Context

  @doc """
  Broadcast a tenant-scoped event.

  Captures the current `Defdo.Tenant.Context`, wraps it in an envelope,
  and broadcasts via the given `pubsub` module.

  ## Parameters

    * `pubsub` — a Phoenix.PubSub-compatible module
    * `topic` — the PubSub topic
    * `event` — event name (atom or string)
    * `payload` — the event payload

  ## Example

      Defdo.Tenant.PubSub.broadcast(
        MyApp.PubSub, "tenant:orders", "order:created", %{order_id: 123}
      )
  """
  @spec broadcast(module(), String.t(), atom() | String.t(), map()) :: :ok | {:error, term()}
  def broadcast(pubsub, topic, event, payload) when is_binary(topic) and is_map(payload) do
    envelope = build_envelope(event, payload)

    pubsub.broadcast(topic, {:tenant_event, envelope})
  end

  @doc """
  Build a tenant-aware envelope without broadcasting.

  Useful when the envelope needs to be sent through a different transport
  (e.g. Redis, RabbitMQ, Kafka).

  Returns the envelope map or raises in strict mode when no context exists.
  """
  @spec build_envelope(atom() | String.t(), map()) :: map()
  def build_envelope(event, payload) when is_map(payload) do
    event_str = to_string(event)

    case Context.capture() do
      %Context{} = ctx ->
        :telemetry.execute(
          [:defdo, :tenant, :pubsub, :published],
          %{count: 1},
          %{event: event_str, scope: ctx.scope}
        )

        %{
          "event" => event_str,
          "payload" => payload,
          "tenant_context" => Context.to_serializable(ctx),
          "published_at" => System.system_time(:second)
        }

      nil ->
        :telemetry.execute(
          [:defdo, :tenant, :pubsub, :context_missing],
          %{count: 1},
          %{event: event_str}
        )

        cond do
          Config.raising?() ->
            raise ArgumentError,
                  "Defdo.Tenant.PubSub broadcast of #{inspect(event_str)} has no tenant context. " <>
                    "Set a context with Defdo.Tenant.with_tenant/2."

          Config.warning?() ->
            require Logger

            Logger.warning(
              "Defdo.Tenant.PubSub broadcast of #{inspect(event_str)} has no tenant context"
            )

          true ->
            :ok
        end

        %{
          "event" => event_str,
          "payload" => payload,
          "published_at" => System.system_time(:second)
        }
    end
  end

  @doc """
  Subscribe to a PubSub topic.

  Wraps `Phoenix.PubSub.subscribe/2`. Messages arrive as
  `{:tenant_event, envelope}` in the subscriber's mailbox.

  ## Example

      def init(_) do
        Defdo.Tenant.PubSub.subscribe(MyApp.PubSub, "tenant:orders")
        {:ok, %{}}
      end
  """
  @spec subscribe(module(), String.t()) :: :ok | {:error, term()}
  def subscribe(pubsub, topic) when is_binary(topic) do
    pubsub.subscribe(topic)
  end

  @doc """
  Handle a received tenant event envelope.

  Restores tenant context from the envelope and executes `fun` with the
  payload. Clears context afterwards.

  Call from your `c:GenServer.handle_info/2`:

      def handle_info({:tenant_event, envelope}, state) do
        Defdo.Tenant.PubSub.handle_message(envelope, fn payload ->
          process_order(payload)
        end)
        {:noreply, state}
      end

  If no context is present in the envelope, enforcement mode applies
  (observe/warn/raise).
  """
  @spec handle_message(map(), (map() -> any())) :: any()
  def handle_message(%{"event" => event} = envelope, fun) when is_function(fun, 1) do
    Context.clear()

    case Map.get(envelope, "tenant_context") do
      map when is_map(map) and map_size(map) > 0 ->
        ctx = Context.from_serializable(map)
        Context.put(ctx)

        :telemetry.execute(
          [:defdo, :tenant, :context, :restored],
          %{count: 1},
          %{boundary: :pubsub, event: event, scope: ctx.scope}
        )

      _ ->
        on_context_missing(event)
    end

    try do
      fun.(envelope["payload"] || %{})
    after
      Context.clear()
    end
  end

  # ── Internals ─────────────────────────────────────────────────────────────────

  defp on_context_missing(event) do
    :telemetry.execute(
      [:defdo, :tenant, :context, :missing],
      %{count: 1},
      %{boundary: :pubsub, event: event}
    )

    cond do
      Config.raising?() ->
        raise ArgumentError,
              "PubSub event #{inspect(event)} has no tenant context in envelope. " <>
                "Use Defdo.Tenant.PubSub.broadcast/4 to attach context."

      Config.warning?() ->
        require Logger
        Logger.warning("PubSub event #{inspect(event)} has no tenant context in envelope")

      true ->
        :ok
    end
  end
end
