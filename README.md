# ActiveRecord::Undo

[![Gem Version](https://img.shields.io/gem/v/active_record-undo.svg?color=blue)](https://rubygems.org/gems/active_record-undo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**ActiveRecord::Undo** brings transactional, cascade-aware soft deletes, instant single-line restores, and a mountable HTTP route engine to Ruby on Rails applications.

Unlike traditional soft-deletion gems that merely flip a timestamp on a single record, `active_record-undo` creates a polymorphic audit log capturing every affected child record across `dependent: :destroy` and `dependent: :delete_all` associations. Restoring a deleted record cleanly recovers the entire deleted subtree in a single atomic database transaction—with out-of-the-box support for multi-tenancy, user attribution, background purging, and zero-boilerplate HTTP endpoints.

---

## Table of Contents

- [Features](#features)
- [Installation \& Migrations](#installation--migrations)
    - [Database Migrations](#database-migrations)
  - [Model Setup](#model-setup)
    - [1. Add Timestamp Column to Tables](#1-add-timestamp-column-to-tables)
    - [2. Declare `acts_as_undoable`](#2-declare-acts_as_undoable)
  - [Basic Usage](#basic-usage)
    - [Cascading Soft Deletes](#cascading-soft-deletes)
    - [Restoring Records](#restoring-records)
      - [Option A: Restore from the model (Recommended)](#option-a-restore-from-the-model-recommended)
      - [Option B: Restore from the `UndoLog`](#option-b-restore-from-the-undolog)
    - [Status \& Eligibility Helpers](#status--eligibility-helpers)
    - [Query Scopes](#query-scopes)
    - [Inspecting Deletion Logs](#inspecting-deletion-logs)
  - [Mountable Route \& Controller Engine](#mountable-route--controller-engine)
    - [Mounting the Engine](#mounting-the-engine)
    - [Available Endpoints](#available-endpoints)
    - [View Helpers (`undo_button_to` \& `undo_link_to`)](#view-helpers-undo_button_to--undo_link_to)
    - [Cryptographic Signed Restore Tokens](#cryptographic-signed-restore-tokens)
      - [Generating \& Using Signed Tokens](#generating--using-signed-tokens)
      - [Key Security Properties](#key-security-properties)
    - [Multi-Format Responses](#multi-format-responses)
    - [Security \& Open-Redirect Protection](#security--open-redirect-protection)
  - [Multi-Tenant Isolation \& User Attribution](#multi-tenant-isolation--user-attribution)
    - [User Attribution (`whodunnit`)](#user-attribution-whodunnit)
    - [Multi-Tenant Scoping](#multi-tenant-scoping)
    - [Tenant Matching Security](#tenant-matching-security)
    - [Configured Context Enforcement](#configured-context-enforcement)
  - [Retention, Expiration \& Purging](#retention-expiration--purging)
    - [Expiration Checks](#expiration-checks)
    - [Purger Service](#purger-service)
    - [ActiveJob Background Worker](#activejob-background-worker)
    - [Rake Task](#rake-task)
  - [Configuration Reference](#configuration-reference)
  - [How It Works](#how-it-works)
  - [Error Reference](#error-reference)
  - [Development](#development)
  - [Contributing](#contributing)
  - [License](#license)

---

## Features

- 🔄 **Cascading Soft Deletes:** Soft deletes parent records along with dependent associations (`dependent: :destroy` / `:delete_all`).
- ⏪ **Atomic Restores:** Reverses soft deletion for an entire object tree (`record.restore!` or `undo_log.restore!`) within a single database transaction.
- 🌐 **Mountable Engine & Endpoints:** Out-of-the-box controller actions for instant undo links with HTML flash redirects, Turbo Streams, and JSON responses.
- 🔒 **Cryptographic Signed Links:** Direct undo restoration tokens (`undo_log.signed_token`) preventing ID enumeration on public or email links.
- 🎨 **Clean View Helpers:** Drop-in `undo_button_to` and `undo_link_to` view helpers for seamless UI integration.
- 🔍 **Restoration Verification (`#undoable?`):** Instantly check if a soft-deleted record is eligible for restore before rendering UI buttons.
- 👤 **User Attribution (`whodunnit`):** Tracks who initiated soft deletes and restores automatically via ambient context or explicit parameters.
- 🏢 **Multi-Tenant Isolation:** Scopes deletion logs to specific tenants with strict tenant-matching security.
- ⚙️ **Custom Soft-Delete Columns:** Supports custom columns (e.g., `:archived_at`, `:discarded_at`) per model while defaulting to `:deleted_at`.
- 🧹 **Retention & Auto-Purging:** Built-in expiration scopes, batch SQL purger, ActiveJob worker, and Rake task with foreign-key constraint protection.
- 🚂 **Zero Generator Setup:** Built as a `Rails::Engine`. Migrations automatically hook into `rails db:migrate`.

---

## Installation & Migrations

Add the gem to your application's `Gemfile`:

```ruby
gem "active_record-undo"
```

Then install dependencies:

```bash
bundle install
```

### Database Migrations

`ActiveRecord::Undo` automatically appends its migrations (`undo_logs` and `undo_log_items`) to your application's migration path:

```bash
rails db:migrate
```

*(Optional)* If you plan to use **Multi-Tenant Isolation** or **User Attribution**, add the polymorphic columns to `undo_logs`:

```ruby
# db/migrate/XXXXXX_add_tenant_and_whodunnit_to_undo_logs.rb
class AddTenantAndWhodunnitToUndoLogs < ActiveRecord::Migration[7.0]
  def change
    change_table :undo_logs, bulk: true do |t|
      t.string :whodunnit_type, null: true
      t.bigint :whodunnit_id, null: true
      t.string :tenant_type, null: true
      t.bigint :tenant_id, null: true
    end

    add_index :undo_logs, [:whodunnit_type, :whodunnit_id], name: "index_undo_logs_on_whodunnit"
    add_index :undo_logs, [:tenant_type, :tenant_id], name: "index_undo_logs_on_tenant"
  end
end
```

*(Optional)* If you wish to customize the gem's core migration directly:

```bash
rails active_record_undo:install:migrations
```

---

## Model Setup

### 1. Add Timestamp Column to Tables

Ensure every model using soft deletion has a timestamp column:

```ruby
class AddDeletedAtToModels < ActiveRecord::Migration[7.0]
  def change
    add_column :posts, :deleted_at, :datetime
    add_column :comments, :deleted_at, :datetime
    add_column :archive_items, :archived_at, :datetime

    add_index :posts, :deleted_at
    add_index :comments, :deleted_at
    add_index :archive_items, :archived_at
  end
end
```

### 2. Declare `acts_as_undoable`

Add `acts_as_undoable` to your models. By default, it uses the `:deleted_at` column:

```ruby
class Post < ApplicationRecord
  acts_as_undoable

  has_many :comments, dependent: :destroy
end

class Comment < ApplicationRecord
  acts_as_undoable

  belongs_to :post
end

class ArchiveItem < ApplicationRecord
  # Configured with a custom timestamp column
  acts_as_undoable column: :archived_at
end
```

---

## Basic Usage

### Cascading Soft Deletes

Call `soft_delete!` on any undoable record. It updates the timestamp column across the record and all dependent associations inside a single database transaction, returning an `ActiveRecord::Undo::UndoLog` instance:

```ruby
post = Post.find(1)

# Soft deletes post and cascades to all associated comments
undo_log = post.soft_delete!

post.soft_deleted?       # => true
post.comments.kept.count # => 0
```

### Restoring Records

You can restore an entire deleted tree either from the model instance or from the `UndoLog`:

#### Option A: Restore from the model (Recommended)

Calling `restore!` directly on the model automatically looks up its latest deletion log, executes the atomic restoration, destroys the log records, and reloads the model instance:

```ruby
post.restore!

post.soft_deleted?  # => false
post.comments.count # => 2
```

#### Option B: Restore from the `UndoLog`

```ruby
undo_log.restore!

post.reload.soft_deleted? # => false
```

### Status & Eligibility Helpers

`ActiveRecord::Undo` provides fast predicate methods and audit helpers on models:

```ruby
# Checks if the soft-delete column is set
post.soft_deleted? # => true / false

# Verifies record is soft-deleted AND has a valid undo log available in the database
post.undoable?     # => true / false

# Checks if the soft-deleted record has exceeded the configured retention period
post.expired?      # => true / false

# Retrieves the latest UndoLog audit record associated with this model
post.undo_log      # => #<ActiveRecord::Undo::UndoLog id: 14, ...>
post.latest_undo_log # alias

# Generates a cryptographic signed restoration token directly from the model
post.signed_token  # => "eyJfcmFpbHMiOnsiZGF0YSI6..."
```

> [!TIP]
> Use `#undoable?` to conditionally display restore buttons in your user interface, passing the model instance directly:
>
> ```erb
> <% if post.undoable? %>
>   <%= undo_button_to(post, text: "Restore") %>
> <% end %>
> ```

### Query Scopes

Filter records easily without writing manual SQL:

```ruby
# Only active (non-deleted) records
Post.kept

# Only soft-deleted records
Post.soft_deleted

# Soft-deleted records past the retention limit
Post.expired

# Retrieve all records including soft-deleted ones
Post.unscoped.all
```

### Inspecting Deletion Logs

Inspect affected records through standard Rails associations on `UndoLog`:

```ruby
undo_log.undo_log_items.map(&:item)
# => [#<Comment id: 101>, #<Comment id: 102>, #<Post id: 1>]
```

---

## Mountable Route & Controller Engine

`active_record-undo` provides a mountable Rails engine route and controller endpoints so host applications can handle undo/restore actions via HTTP requests without writing boilerplate controller logic.

### Mounting the Engine

Mount the engine in your application routes:

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount ActiveRecord::Undo::Engine => "/undo"
end
```

### Available Endpoints

| Method | Route                    | Controller#Action                    | Description                                |
| :----- | :----------------------- | :----------------------------------- | :----------------------------------------- |
| `POST` | `/undo/logs/:id/restore` | `active_record/undo/logs#restore`    | Restores an `UndoLog` by ID                |
| `POST` | `/undo/restore/:token`   | `active_record/undo/restores#create` | Restores an `UndoLog` using a signed token |

### View Helpers (`undo_button_to` & `undo_link_to`)

Clean view helpers are automatically available in all Rails views and forms:

```erb
<%# Standard button_to targeting /undo/logs/:id/restore %>
<%= undo_button_to(@undo_log) %>

<%# Pass model instances directly %>
<%= undo_button_to(post, text: "Undo Delete", class: "btn btn-primary") %>

<%# Secure direct link with signed token (prevents ID enumeration in emails or public links) %>
<%= undo_button_to(@undo_log, signed: true, class: "btn btn-success") %>

<%# Turbo Stream / Hotwire compatible link %>
<%= undo_link_to(@undo_log, text: "Undo", class: "text-decoration-underline") %>
<%= undo_link_to(@undo_log, signed: true) %>
```

### Cryptographic Signed Restore Tokens

When exposing restore actions in flash notifications, transactional emails, webhook alerts, or public interfaces, relying on sequential database IDs (e.g., `POST /undo/logs/42/restore`) can expose your application to ID enumeration attacks.

`active_record-undo` provides signed tokens for restoration via tamper-proof, opaque URLs: `POST /undo/restore/:token`.

#### Generating & Using Signed Tokens

**In Views (using helpers):**

```erb
<%# Renders a form POST to /undo/restore/:token %>
<%= undo_button_to(post, signed: true, text: "Undo Delete", class: "btn btn-outline-primary") %>

<%# Renders an anchor tag for Turbo / Hotwire %>
<%= undo_link_to(post, signed: true, text: "Undo") %>
```

**In Controllers, Background Jobs & Mailers:**

```ruby
# Generate token directly from the model instance
token = post.signed_token

# Or with a custom expiration window
token = post.signed_token(expires_in: 2.hours)

# Or directly from an UndoLog instance
token = undo_log.signed_token

# Construct full URL for transactional emails or Slack webhooks
restore_url = active_record_undo.signed_restore_url(token: token)
```

**Manual Verification & Retrieval:**

```ruby
# Manually verify and retrieve the associated UndoLog
undo_log = ActiveRecord::Undo::UndoLog.find_by_signed_token(params[:token])
```

#### Key Security Properties

1. **HMAC-SHA256 Cryptographic Tamper Resistance:** Tokens are signed using `Rails.application.message_verifier(:active_record_undo)` derived securely from your application's `secret_key_base`. Any payload alteration invalidates the cryptographic signature.
2. **Purpose Isolation (`purpose: :restore`):** Tokens are strictly scoped to restoration. Tokens generated for other purposes (or by other verifiers) are rejected.
3. **Time-Limited Lifespan:** Tokens include an embedded expiration timestamp (configurable via `config.token_expires_in`, defaults to `24.hours`). Expired tokens are rejected automatically.
4. **Single-Use Replay Protection:** When `undo_log.restore!` succeeds, it automatically destroys the `UndoLog` and its associated items from the database (`destroy!`). Even if an attacker or user resubmits the signed token before its cryptographic expiration, the database lookup fails and returns `nil`, rendering a `404 Not Found`.
5. **Multi-Tenant Authorization:** Cryptographic validity only proves the token was authentic. During execution, `undo_log.restore!` still enforces multi-tenant boundary matching against `ActiveRecord::Undo.current_tenant`. An authenticated user from Tenant B cannot use a token from Tenant A to restore data.

### Multi-Format Responses

The engine controller seamlessly handles multiple response formats:

- **HTML:** Redirects to `params[:redirect_to]` (if a validated safe URL), `request.referer`, or `config.default_redirect_path` with a flash notice (`flash[:notice] = "Record successfully restored."`).
- **Turbo Stream (`text/vnd.turbo-stream.html`):** Renders inline `<turbo-stream>` notification elements with HTTP status `200 OK`.
- **JSON:** Returns `{ "success": true, "restored_items_count": count }` with HTTP status `200 OK`.

In error scenarios (missing record, expired action, or security mismatch):

- **`403 Forbidden`:** Rendered on `ActiveRecord::Undo::SecurityError` (or HTML redirected with `flash[:alert]`).
- **`404 Not Found`:** Rendered when the undo log does not exist or has already been restored.
- **`422 Unprocessable Content`:** Rendered when the undo action has expired beyond the retention period.

### Security & Open-Redirect Protection

- **CSRF Protection:** Inherits from `ActionController::Base` (or your configured `base_controller`) with CSRF verification enabled.
- **Open-Redirect Mitigation:** `params[:redirect_to]` and `request.referer` undergo strict URL validation. Only relative paths or URLs matching the request's exact host and port are accepted; foreign or protocol-relative URLs (e.g., `//evil.com`) are rejected in favor of the safe fallback.
- **Signed Tokens:** `undo_log.signed_token` uses Rails' `message_verifier(:active_record_undo)` to sign tokens cryptographically, preventing tampering, replay, and ID enumeration.

---

## Multi-Tenant Isolation & User Attribution

To support enterprise-grade Rails applications, `active_record-undo` natively integrates user auditing and tenant scoping.

### User Attribution (`whodunnit`)

Track which user initiated a soft deletion or restoration:

```ruby
# 1. Via explicit parameter
post.soft_delete!(whodunnit: current_user)
post.restore!(whodunnit: current_user)

# 2. Via Thread / Fiber ambient context
ActiveRecord::Undo.whodunnit = current_user
post.soft_delete!

# 3. Via global callable proc
ActiveRecord::Undo.configure do |config|
  config.current_user_method = -> { Current.user }
end
```

### Multi-Tenant Scoping

Scope soft deletes and logs to accounts or organizations:

```ruby
# 1. Via explicit parameter
post.soft_delete!(tenant: current_account)

# 2. Via Thread / Fiber ambient context
ActiveRecord::Undo.current_tenant = current_account
post.soft_delete!

# 3. Via global callable proc
ActiveRecord::Undo.configure do |config|
  config.current_tenant_method = -> { Current.account }
end
```

### Tenant Matching Security

When restoring a log belonging to a tenant, the gem verifies that the executing context's tenant matches the log's tenant. If there is a mismatch or missing tenant context, an `ActiveRecord::Undo::SecurityError` is raised:

```ruby
ActiveRecord::Undo.current_tenant = wrong_account
post.restore! # => raises ActiveRecord::Undo::SecurityError (Tenant mismatch)
```

### Configured Context Enforcement

When `current_user_method` or `current_tenant_method` is configured via `ActiveRecord::Undo.configure`, operations ensure the context does not evaluate to `nil`:

```ruby
# If current_user_method evaluates to nil (e.g., unauthenticated request):
post.soft_delete! # => raises ActiveRecord::Undo::SecurityError: Configured current_user_method returned nil.
```

*(If neither method is configured, operations proceed normally without requiring user or tenant context).*

---

## Retention, Expiration & Purging

To keep your database lean, `active_record-undo` provides retention management and automated background purging.

### Expiration Checks

Query and check expired records using the configured retention window (default: `30.days`):

```ruby
# Scopes
Post.expired                        # Soft-deleted posts older than retention period
ActiveRecord::Undo::UndoLog.expired # Undo logs older than retention period

# Predicates
post.expired?     # => true / false
undo_log.expired? # => true / false
```

### Purger Service

`ActiveRecord::Undo::Purger` performs batch SQL deletes bypassing model callbacks for peak efficiency:

```ruby
# Purge all expired records and logs across registered models
ActiveRecord::Undo::Purger.purge_expired!(batch_size: 1000)

# Scoped purge for a specific tenant
ActiveRecord::Undo.current_tenant = account_1
ActiveRecord::Undo::Purger.purge_expired!
```

> [!NOTE]
> **Relational Integrity Protection:** To prevent foreign-key constraint violations (`FOREIGN KEY constraint failed`), `Purger` dynamically resolves dependent associations (`:destroy`, `:delete_all`, `:soft_delete`) and recursively cleans up child records bottom-up before purging parent records. For `:nullify` associations, foreign keys are nullified (or cascaded if restricted by a `NOT NULL` constraint).

### ActiveJob Background Worker

Enqueue purges easily via ActiveJob:

```ruby
ActiveRecord::Undo::PurgeJob.perform_later(batch_size: 1000)
```

### Rake Task

Run purging from cron, cron-like schedulers, or CI:

```bash
# Default batch size (1000)
rails active_record_undo:purge_expired

# Custom batch size
BATCH_SIZE=500 rails active_record_undo:purge_expired
```

---

## Configuration Reference

Configure all gem options in a single initializer:

```ruby
# config/initializers/active_record_undo.rb
ActiveRecord::Undo.configure do |config|
  # Default retention period for soft-deleted records and undo logs (defaults to 30.days)
  # Set to nil to disable expiration
  config.retention_period = 30.days

  # Callable procs to resolve ambient user and tenant context (defaults to nil)
  config.current_user_method   = -> { Current.user }
  config.current_tenant_method = -> { Current.account }

  # Base controller for engine authentication and authorization hooks
  # Defaults to "::ApplicationController" if defined, falling back to ActionController::Base
  config.base_controller = "::ApplicationController"

  # Fallback redirect path after successful restore when no redirect_to or referer exists
  config.default_redirect_path = ->(main_app) { main_app.root_path }

  # Expiration duration for signed restore tokens (defaults to 24.hours)
  config.token_expires_in = 24.hours

  # Custom secret key for signed tokens (defaults to nil, utilizing Rails application verifier)
  config.token_secret_key = nil

  # Error handling strategy for HTML requests (:auto, :redirect, or :render)
  # Defaults to :auto (redirects with flash alert if referer/redirect_to present, else renders status)
  config.error_handling = :auto
end
```

---

## How It Works

1. **Cascade Inspection:** On calling `soft_delete!`, `ActiveRecord::Undo::CascadeHandler` reflects on `has_many`, `has_one`, and `belongs_to` associations configured with `dependent: :destroy` or `:delete_all`.
2. **Column Resolution:** Identifies `record.class.undoable_column` to apply the correct timestamp column (`:deleted_at`, `:archived_at`, etc.) across all affected models.
3. **Audit Logging:** Creates an `UndoLog` and individual `UndoLogItem` entries storing polymorphic references (`item_type`, `item_id`) for every soft-deleted record.
4. **Atomic Operation:** Deletions and log creations execute within a single `ActiveRecord::Base.transaction`.
5. **Reverse Restoration:** Calling `restore!` executes within a transaction, iterating over items in reverse order (`reverse_each`) so parent and dependent records are re-activated in the proper sequence before purging the log.

---

## Error Reference

| Error Class                         | Trigger Scenario                                                              |
| :---------------------------------- | :---------------------------------------------------------------------------- |
| `ActiveRecord::Undo::Error`         | The configured soft-delete column does not exist on the table.                |
| `ActiveRecord::Undo::Error`         | A model class referenced by an `UndoLogItem` was renamed or deleted.          |
| `ActiveRecord::Undo::SecurityError` | Attempted restore where the context's tenant does not match the log's tenant. |
| `ActiveRecord::Undo::SecurityError` | Attempted restore of a tenant-scoped log when no tenant is set in context.    |
| `ActiveRecord::Undo::SecurityError` | Configured `current_user_method` or `current_tenant_method` returned `nil`.   |

---

## Development

Clone the repository and install dependencies:

```bash
git clone https://github.com/saurabh-activecode/active_record-undo.git
cd active_record-undo
bundle install
```

Run test suite via RSpec:

```bash
bundle exec rspec
```

Run RuboCop linting:

```bash
bundle exec rubocop
```

---

## Contributing

Bug reports and pull requests are welcome on GitHub at [https://github.com/saurabh-activecode/active_record-undo](https://github.com/saurabh-activecode/active_record-undo).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
