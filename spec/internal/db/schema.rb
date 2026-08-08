# spec/internal/db/schema.rb
# frozen_string_literal: true

ActiveRecord::Schema.define do
  create_table :posts, force: true do |t|
    t.string :title
    t.datetime :deleted_at
    t.timestamps
  end

  create_table :comments, force: true do |t|
    t.text :body
    t.references :post
    t.references :comment
    t.datetime :deleted_at
    t.timestamps
  end

  create_table :archive_items, force: true do |t|
    t.string :name
    t.datetime :archived_at
    t.timestamps
  end

  create_table :likes, force: true do |t|
    t.references :post
    t.datetime :deleted_at
    t.timestamps
  end
end
