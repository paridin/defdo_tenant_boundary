# 0.1.0

Initial release of the Defdo Tenant Boundary Kit — cross-process wrappers.

- `Defdo.Tenant.Oban` — tenant-safe job insertion; captures `Context` into job `meta`.
- `Defdo.Tenant.Worker` — `use` macro wrapping `perform/1` with context restore;
  implement `perform_with_tenant/1` instead of `perform/1`.
- `Defdo.Tenant.GenServer` — `capture_init_context/0` + `restore_context/0` helpers
  for explicit context management in GenServer callbacks.
- `Defdo.Tenant.PubSub` — tenant-aware envelope: `broadcast/4`, `subscribe/2`,
  `handle_message/2`, `build_envelope/2`.
- `Defdo.Tenant.Webhook` — two-phase trusted-edge resolution: `resolve/2` with
  built-in `:host` and `:domain` resolvers + custom MFA; `execute/2` for scoped logic.
- `Defdo.Tenant.Cache` — `key/1` prefixes with tenant ID; `global_key/1` for shared keys.
- `Defdo.Tenant.Storage` — `path/1` prefixes with `tenants/:id/`; `global_path/1` for shared.

All wrappers respect `Defdo.Tenant.Config` enforcement modes (`:observe`, `:warn`,
`:test_enforce`, `:strict`) and emit telemetry events for context capture, restore,
and missing events.
