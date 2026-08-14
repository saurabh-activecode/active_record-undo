# ActiveRecord::Undo

[![Gem Version](https://img.shields.io/gem/v/active_record-undo.svg?color=blue)](https://rubygems.org/gems/active_record-undo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**ActiveRecord::Undo** brings transactional, cascade-aware soft deletes and automatic restores to Rails applications.

Unlike conventional soft-deletion gems, `active_record-undo` automatically captures an audit snapshot of all records affected across associations (e.g., dependent `has_many` or `has_one` relations) and tracks them in a dedicated polymorphic undo log. Restoring a deleted record cleanly restores its entire deleted child tree in a single atomic database transaction.

---

## Features

- 🔄 **Cascading Soft Deletes:** Soft deletes parent models along with dependent associations (`dependent: :destroy` / `:delete_all`).
- ⏪ **Atomic Restores:** Reverses soft deletion for an entire object tree (`undo_log.restore!` or `record.restore!`) within a single database transaction.
- 🔍 **Restoration Verification:** Provides `#undoable?` to check if a record is soft-deleted and has a valid undo log entry available for restoration.
- ⚙️ **Configurable Columns:** Supports custom soft-delete columns (e.g., `:archived_at`, `:discarded_at`) per model while defaulting to `:deleted_at`.
- 📦 **Polymorphic Tracking:** Records deletion events via native `UndoLog` and `UndoLogItem` models—no messy JSON payload parsing required.
- 🚂 **Zero Generator Setup:** Built on top of `Rails::Engine`. Migrations automatically hook into `rails db:migrate`.
- 🔍 **Default Scopes & Helpers:** Provides `.kept`, `.soft_deleted`, `#soft_deleted?`, and `#undoable?` query methods out of the box.
- 🧹 **Automatic Expiration & Purging:** Configurable global retention window with automated background purging (`PurgeJob` and Rake task) to clean up old soft-deleted records and logs.

---

## Installation

Add this line to your application's `Gemfile`:

```ruby
gem "active_record-undo"
```

Then execute:

```bash
$ bundle install
```

Run database migrations. The gem automatically appends its tables (`undo_logs` and `undo_log_items`) to your app's migration path:

```bash
$ rails db:migrate
```

*(Optional)* If you need to customize the migration, copy it to your host application's `db/migrate` folder:

```bash
$ rails active_record_undo:install:migrations
```

---

## Usage

### 1. Database Setup

Ensure models using soft deletion have a timestamp column in their underlying database table:

```ruby
class AddSoftDeleteColumnsToModels < ActiveRecord::Migration[7.0]
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

### 2. Configure Models

Add `acts_as_undoable` to models where you want soft deletion enabled. By default, it uses `:deleted_at`, but you can pass a custom column name:

```ruby
class Post < ApplicationRecord
  # Uses default :deleted_at column
  acts_as_undoable

  has_many :comments, dependent: :destroy
end

class Comment < ApplicationRecord
  # Uses default :deleted_at column
  acts_as_undoable

  belongs_to :post
end

class ArchiveItem < ApplicationRecord
  # Configured with a custom column
  acts_as_undoable column: :archived_at
end
```

---

## Quick Start Guide

### Soft Delete & Cascade

Call `soft_delete!` on a record. It sets the configured soft-delete column across the record and its dependent relations inside a single transaction, returning an `ActiveRecord::Undo::UndoLog` instance:

```ruby
post = Post.find(1)

# Soft deletes post and all associated comments
undo_log = post.soft_delete!

post.soft_deleted? # => true
post.comments.kept.count # => 0
```

### Custom Column Usage

```ruby
item = ArchiveItem.find(5)
item.soft_delete!

item.soft_deleted? # => true
item.archived_at   # => 2026-08-08 22:20:16 UTC
```

### Checking Restoration Eligibility (`#undoable?`)

Use `#undoable?` to verify if a record is soft-deleted and has a corresponding `UndoLog` entry available in the database. This is ideal for conditionally rendering UI elements or validating controller actions:

```ruby
post = Post.unscoped.find(1)

if post.undoable?
  # Render "Undo Deletion" button or execute restore
  post.restore!
end
```

`#undoable?` returns `false` if:
* The record is currently active (not soft deleted).
* The record was soft deleted manually via direct SQL/column updates without generating an undo log.
* The corresponding `UndoLog` record was purged or already restored.

### Inspect Deletion Logs

Inspect affected records through standard Rails associations on the returned `UndoLog`:

```ruby
# List all items affected by this deletion event
undo_log.undo_log_items.map(&:item)
# => [#<Comment 101... id:>, #<Comment 102... id:>, #<Post 1... id:>]
```

### Restoring Records

To restore a deleted object tree, you can invoke `restore!` either on the corresponding `UndoLog` or directly on the model instance itself:

#### Option A: Restore from the model instance (Recommended)
Calling `restore!` directly on the soft-deleted model automatically resolves its latest deletion event log, performs the cascading restore, and cleans up the log database rows:

```ruby
# Restores the post and all comments deleted in the same batch
post.restore!

post.reload.soft_deleted? # => false
post.comments.count       # => 2
```

#### Option B: Restore from the `UndoLog`
```ruby
# Reverses soft deletes for the post and comments
undo_log.restore!

post.reload.soft_deleted? # => false
post.comments.count       # => 2
```

---

## Scopes & Querying

`ActiveRecord::Undo` provides scopes and predicate helpers for filtering and checking records based on the configured column:

```ruby
# Fetch only active (non-deleted) records
Post.kept

# Fetch soft-deleted records
Post.soft_deleted

# Check if a record is soft-deleted
post.soft_deleted?

# Check if a record is soft-deleted AND can be restored via an undo log
post.undoable?

# Retrieve records including soft-deleted ones via unscoped
Post.unscoped.where(id: 1)
```

---

## Expiration, Retention & Auto-Purging

To prevent database bloat, `active_record-undo` supports automated retention periods, expiration checks, and background purging for both soft-deleted records and their associated `UndoLog` audit entries.

### 1. Global Configuration

You can configure a global retention period inside a Rails initializer:

```ruby
# config/initializers/active_record_undo.rb
ActiveRecord::Undo.configure do |config|
  # Default retention period for all soft-deleted records and undo logs (defaults to 30.days)
  config.retention_period = 30.days
end
```

If `retention_period` is set to `nil`, records and logs will never expire.

### 2. Expiration Scopes & Helpers

The gem provides query scopes and instance predicate helpers:

- **Model `.expired` Scope**: Returns soft-deleted records older than the configured retention period.
  ```ruby
  Post.expired # => ActiveRecord::Relation of posts soft-deleted > 30 days ago
  ```
- **Model `#expired?` Predicate**: Checks if a record is soft-deleted and past the retention period.
  ```ruby
  post.expired? # => true/false
  ```
- **`UndoLog.expired` Scope**: Returns undo log entries older than the retention period.
  ```ruby
  ActiveRecord::Undo::UndoLog.expired # => logs created > 30 days ago
  ```

### 3. Background Purging

#### Purger Service
The `ActiveRecord::Undo::Purger` class performs hard SQL deletes on expired records and logs using `delete_all` (bypassing callbacks and validations for efficiency):

```ruby
# Purge all expired soft-deleted records and undo logs in batches
ActiveRecord::Undo::Purger.purge_expired!(batch_size: 1000)
```

> [!NOTE]
> **Relational Integrity & Orphan Prevention**: Because the retention period is globally unified, parent and child records soft-deleted together share the exact same deletion timestamp and expiration threshold. Therefore, when the purger runs, both parent and child records expire and are hard-deleted in the same run, completely preventing the creation of orphaned records in your database.

#### ActiveJob Background Job
The gem provides an ActiveJob class that calls the Purger service:

```ruby
# Enqueue the purge job to run in the background
ActiveRecord::Undo::PurgeJob.perform_later(batch_size: 1000)
```

#### Engine Rake Task
You can run the purge task via Rake. This task is automatically loaded into host applications:

```bash
# Run with the default batch size of 1000
$ rails active_record_undo:purge_expired

# Run with a custom batch size
$ BATCH_SIZE=500 rails active_record_undo:purge_expired
```

---

## How It Works

1. **Cascade Inspection:** When `soft_delete!` is called, `ActiveRecord::Undo::CascadeHandler` reflects on `has_many`, `has_one`, and `belongs_to` associations configured with `dependent: :destroy` or `:delete_all`.
2. **Dynamic Column Resolution:** The handler checks `record.class.undoable_column` to set the correct timestamp column (`:deleted_at`, `:archived_at`, etc.) across all affected models.
3. **Polymorphic Logging:** An `ActiveRecord::Undo::UndoLog` record is created alongside multiple `ActiveRecord::Undo::UndoLogItem` entries mapping polymorphic references (`item_type`, `item_id`) to every affected record.
4. **Restoration Verification:** Calling `#undoable?` executes an efficient SQL query joining `undo_log_items` and `undo_logs` to ensure the entity is soft-deleted and its associated log entry exists before restoration.
5. **Atomic Operation:** All updates and log creations take place within an `ActiveRecord::Base.transaction`.

---

## Error Handling

To ensure database integrity and provide clear debugging context, the gem raises an `ActiveRecord::Undo::Error` in the following scenarios:
* **Missing Column at Runtime:** If the configured soft-delete column is missing from the database table when calling `soft_delete!` or `restore!`.
* **Missing Model Class:** If a model class has been renamed or deleted, preventing the polymorphic log items from finding the target class during restore.
* **Missing Column on Target Class:** If a model class exists but no longer has the target soft-delete column during restore.

---

## Development

After cloning the repository, install dependencies:

```bash
$ bundle install
```

Run test suite via RSpec:

```bash
$ bundle exec rspec
```

---

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/saurabh-activecode/active_record-undo.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).