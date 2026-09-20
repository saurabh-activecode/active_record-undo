# frozen_string_literal: true

module ActiveRecord
  module Undo
    module ModelExtension
      module AsyncMethods
        def soft_delete_status
          return nil unless soft_deleted?
          return 'completed' unless undo_log

          undo_log.soft_delete_status
        end

        def restore_status
          return nil unless undo_log

          undo_log.restore_status
        end

        def soft_delete_later!(whodunnit: nil, tenant: nil, queue: nil)
          ensure_undoable_column_exists!
          return false if soft_deleted?

          ActiveRecord::Undo.verify_configured_context!
          attrs = build_undo_log_attributes(whodunnit, tenant)
          undo_log = execute_initial_soft_delete_later!(attrs)
          enqueue_soft_delete_job!(undo_log, whodunnit, tenant, queue)
          undo_log
        end

        def restore_later!(whodunnit: nil, queue: nil)
          ensure_undoable_column_exists!
          return false unless soft_deleted?

          ActiveRecord::Undo.verify_configured_context!
          log = undo_log
          raise ActiveRecord::Undo::Error, 'No undo log found to restore.' unless log

          log.restore_later!(whodunnit: whodunnit, queue: queue)
          log
        end

        private

        def execute_initial_soft_delete_later!(attrs)
          transaction do
            timestamp = Time.current
            undo_log = ActiveRecord::Undo::UndoLog.create!(attrs.merge(action: :soft_delete, status: :pending))
            update_soft_delete_timestamps!(timestamp)
            ActiveRecord::Undo::UndoLogItem.create!(undo_log_id: undo_log.id, item: self)
            undo_log
          end
        end

        def update_soft_delete_timestamps!(timestamp)
          column_name = self.class.undoable_column
          update_columns(column_name => timestamp, updated_at: timestamp)
        end

        def enqueue_soft_delete_job!(undo_log, whodunnit, tenant, queue)
          job_class = ActiveRecord::Undo::SoftDeleteJob
          job = queue.present? ? job_class.set(queue: queue) : job_class
          job.perform_later(self.class.name, id, undo_log.id, whodunnit: whodunnit, tenant: tenant)
        end
      end
    end
  end
end
