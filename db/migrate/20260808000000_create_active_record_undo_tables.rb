# db/migrate/20260808000000_create_active_record_undo_tables.rb
# frozen_string_literal: true

class CreateActiveRecordUndoTables < ActiveRecord::Migration[7.0]
  def change
    create_table :undo_logs, &:timestamps

    create_table :undo_log_items do |t|
      t.references :undo_log, null: false, foreign_key: { to_table: :undo_logs }
      t.references :item, polymorphic: true, null: false
      t.timestamps
    end

    add_index :undo_log_items, %i[item_type item_id]
  end
end
