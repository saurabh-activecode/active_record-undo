# db/migrate/20260821000000_add_tenant_and_user_attribution_to_undo_logs.rb
# frozen_string_literal: true

class AddTenantAndUserAttributionToUndoLogs < ActiveRecord::Migration[7.0]
  def change
    change_table :undo_logs, bulk: true do |t|
      t.string :whodunnit_type, null: true
      t.bigint :whodunnit_id, null: true
      t.string :tenant_type, null: true
      t.bigint :tenant_id, null: true
    end

    add_index :undo_logs, %i[whodunnit_type whodunnit_id], name: 'index_undo_logs_on_whodunnit'
    add_index :undo_logs, %i[tenant_type tenant_id], name: 'index_undo_logs_on_tenant'
  end
end
