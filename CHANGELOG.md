# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-10-24

### Added

- **Asynchronous Cascades & Background Workers**:
  - `record.soft_delete_later!(whodunnit: ..., tenant: ..., queue: ...)`: Marks the root record immediately, creates an audit `UndoLog`, and enqueues `SoftDeleteJob` for background cascading.
  - `record.restore_later!(whodunnit: ..., queue: ...)` and `undo_log.restore_later!(...)`: Schedules bottom-up batch restoration in the background via `RestoreJob`.
  - Configurable `config.base_job` (defaults to `"::ActiveJob::Base"`) allowing custom application worker classes with custom retry and error handling logic.
- **Persistent State Tracking & Observability**:
  - Migration `AddStatusAndErrorMessageToUndoLogs` adding `status` enum (`pending`, `processing`, `completed`, `failed`), `action` enum (`soft_delete`, `restore`), and persistent `error_message` text column with database indexes.
  - Dedicated status polling HTTP endpoints: `GET /undo/logs/:id/status` and `GET /undo/status/:token`.
  - Asynchronous restore support on HTTP endpoints: `POST /undo/logs/:id/restore` and `POST /undo/restore/:token` via `params: { async: true }` or `X-Undo-Async: true` header, returning `202 Accepted` in JSON and Turbo Stream formats.
- **Idempotency, Concurrency & Retry Resilience**:
  - Row-level database locking (`with_lock`) in `RestoreJob` and `SoftDeleteJob` to prevent duplicate or concurrent worker runs.
  - Idempotent re-entrancy in `CascadeHandler#soft_delete_associations_batched!` with `associated.reload.soft_deleted?` pre-checks.
  - Safe retry support for failed operations (`UndoLog#restore!` and `UndoLog#restore_later!`).
  - ActiveJob worker exception re-raising after logging failure to allow native queue retries (`retry_on`) and APM/error monitoring alerts (Sentry, Bugsnag).
- **Execution State Predicates & View Helpers**:
  - Model and UndoLog predicate methods: `soft_delete_status`, `restore_status`, `soft_delete_pending?`, `soft_delete_processing?`, `soft_delete_completed?`, `soft_delete_failed?`, `restore_pending?`, `restore_processing?`, `restore_failed?`.
  - Status badge view helpers: `undo_status_badge(target, action: :auto, **options)`, `soft_delete_status_badge(target, **options)`, and `restore_status_badge(target, **options)`.
- **Security & Multi-Tenancy**:
  - Strict tenant boundary security enforcement on all async restore endpoints and status check routes.
  - Automatic tenant context propagation to background worker threads during asynchronous restoration.

## [0.2.0] - 2026-08-25

### Added

- Mountable Rails engine (`ActiveRecord::Undo::Engine`) and RESTful restore endpoints (`POST /undo/logs/:id/restore` and `POST /undo/restore/:token`).
- Cryptographic signed token verification (`token_verifier`) for tamper-proof direct-link restoration without exposing database IDs.
- ActionView helpers: `undo_button_to` and `undo_link_to` supporting both log instances and model objects.
- Open-redirect protection (`SafeRedirect`) preventing open-redirect and protocol-relative phishing attacks.
- Global engine configuration: `base_controller`, `default_redirect_path`, `token_secret_key`, `token_expires_in`, and `error_handling`.

## [0.1.5] - 2026-08-21

### Added

- User attribution (`whodunnit`) and multi-tenant isolation support.
- Migration `AddTenantAndUserAttributionToUndoLogs` for polymorphic attribution.
- Ambient thread/fiber context: `ActiveRecord::Undo.whodunnit` and `ActiveRecord::Undo.current_tenant`.
- Strict tenant verification during restore operations.

## [0.1.4] - 2026-08-14

### Added

- Hard purging engine (`ActiveRecord::Undo::Purger`) for cleaning up expired records and audit logs.
- Background purge job (`ActiveRecord::Undo::PurgeJob`) and `rake active_record_undo:purge_expired` task.
- Retention period management via `config.retention_period` and model `.expired` scope.

## [0.1.3] - 2026-08-11

### Added

- `undoable?` predicate helper on undoable models.

## [0.1.2] - 2026-08-09

### Added

- CI and Shields.io status badges to documentation.

## [0.1.1] - 2026-08-09

### Changed

- Updated gem publishing GitHub Actions workflow.

## [0.1.0] - 2026-08-08

### Added

- Initial release: core `acts_as_undoable` macro, `soft_delete!`, `restore!`, cascading deletions, `UndoLog`, and `UndoLogItem`.
