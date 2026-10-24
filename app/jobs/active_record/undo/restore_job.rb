# frozen_string_literal: true

module ActiveRecord
  module Undo
    class RestoreJob < ActiveRecord::Undo.base_job_class
      queue_as :default

      def perform(undo_log_id, whodunnit: nil)
        undo_log = find_undo_log(undo_log_id)
        return unless undo_log

        acquired = lock_and_start_processing!(undo_log)
        return unless acquired

        execute_restore_batches(undo_log, whodunnit)
      rescue StandardError => e
        handle_failure(undo_log, e)
        raise e
      end

      private

      def find_undo_log(undo_log_id)
        ActiveRecord::Undo::UndoLog.find_by(id: undo_log_id)
      end

      def lock_and_start_processing!(undo_log)
        undo_log.with_lock do
          return false if undo_log.processing?
          return false if undo_log.completed?

          undo_log.update!(status: :processing)
          true
        end
      end

      def execute_restore_batches(undo_log, whodunnit)
        actor = undo_log.send(:resolve_whodunnit, whodunnit)
        undo_log.send(:with_whodunnit_context, actor) do
          with_tenant_context(undo_log) do
            restore_all_items_in_batches(undo_log)
            cleanup_log!(undo_log)
          end
        end
      end

      def with_tenant_context(undo_log)
        ten = undo_log.tenant || undo_log.tenant_id
        orig = ActiveRecord::Undo.current_tenant
        ActiveRecord::Undo.current_tenant = ten if ten.present?
        yield
      ensure
        ActiveRecord::Undo.current_tenant = orig
      end

      def restore_all_items_in_batches(undo_log)
        undo_log.undo_log_items.find_each(batch_size: 1000, order: :desc, &:restore_item!)
      end

      def cleanup_log!(undo_log)
        undo_log.undo_log_items.in_batches(of: 1000).delete_all
        undo_log.destroy!
      end

      def handle_failure(undo_log, exception)
        return unless undo_log && ActiveRecord::Undo::UndoLog.exists?(undo_log.id)

        undo_log.update!(status: :failed, error_message: exception.message)
      end
    end
  end
end
