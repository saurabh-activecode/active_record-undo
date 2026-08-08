# ActiveRecord::Undo

[![Gem Version](https://badge.fury.io/rb/active_record-undo.svg)](https://badge.fury.io/rb/active_record-undo)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**ActiveRecord::Undo** brings transactional, cascade-aware soft deletes and automatic restores to Rails applications.

Unlike conventional soft-deletion gems, `active_record-undo` automatically captures an audit snapshot of all records affected across associations (e.g., dependent `has_many` or `has_one` relations) and tracks them in a dedicated polymorphic undo log. Restoring a deleted record cleanly restores its entire deleted child tree in a single atomic database transaction.

---

## Features

- 🔄 **Cascading Soft Deletes:** Soft deletes parent models along with dependent associations (`dependent: :destroy` / `:delete_all`).
- ⏪ **Atomic Restores:** Reverses soft deletion for an entire object tree (`undo_log.restore!`) within a single database transaction.
- ⚙️ **Configurable Columns:** Supports custom soft-delete columns (e.g., `:archived_at`, `:discarded_at`) per model while defaulting to `:deleted_at`.
- 📦 **Polymorphic Tracking:** Records deletion events via native `UndoLog` and `UndoLogItem` models—no messy JSON payload parsing required.
- 🚂 **Zero Generator Setup:** Built on top of `Rails::Engine`. Migrations automatically hook into `rails db:migrate`.
- 🔍 **Default Scopes & Helpers:** Provides `.kept`, `.soft_deleted`, and `#soft_deleted?` query methods out of the box.

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

`ActiveRecord::Undo` provides scopes for filtering records based on the configured column:

```ruby
# Fetch only active (non-deleted) records
Post.kept

# Fetch soft-deleted records
Post.soft_deleted

# Retrieve records including soft-deleted ones via unscoped
Post.unscoped.where(id: 1)
```

---

## How It Works

1. **Cascade Inspection:** When `soft_delete!` is called, `ActiveRecord::Undo::CascadeHandler` reflects on `has_many`, `has_one`, and `belongs_to` associations configured with `dependent: :destroy` or `:delete_all`.
2. **Dynamic Column Resolution:** The handler checks `record.class.undoable_column` to set the correct timestamp column (`:deleted_at`, `:archived_at`, etc.) across all affected models.
3. **Polymorphic Logging:** An `ActiveRecord::Undo::UndoLog` record is created alongside multiple `ActiveRecord::Undo::UndoLogItem` entries mapping polymorphic references (`item_type`, `item_id`) to every affected record.
4. **Atomic Operation:** All updates and log creations take place within an `ActiveRecord::Base.transaction`.

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