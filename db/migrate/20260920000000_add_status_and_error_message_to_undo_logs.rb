# db/migrate/20260920000000_add_status_and_error_message_to_undo_logs.rb
# frozen_string_literal: true

class AddStatusAndErrorMessageToUndoLogs < ActiveRecord::Migration[7.0]
  def change
    change_table :undo_logs, bulk: true do |t|
      t.integer :status, default: 2, null: false unless column_exists?(:undo_logs, :status)
      t.integer :action, default: 0, null: false unless column_exists?(:undo_logs, :action)
      t.text :error_message unless column_exists?(:undo_logs, :error_message)
    end

    add_index :undo_logs, :status unless index_exists?(:undo_logs, :status)
    add_index :undo_logs, :action unless index_exists?(:undo_logs, :action)
  end
end
