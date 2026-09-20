# frozen_string_literal: true

module ActiveRecord
  module Undo
    class SoftDeleteJob < ActiveRecord::Undo.base_job_class
      queue_as :default

      def perform(record_class_name, record_id, undo_log_id, whodunnit: nil, tenant: nil)
        undo_log = find_undo_log(undo_log_id)
        return unless undo_log

        execute_soft_delete_cascade(record_class_name, record_id, undo_log, whodunnit, tenant)
      rescue StandardError => e
        handle_failure(undo_log, e)
        raise e
      end

      private

      def find_undo_log(undo_log_id)
        ActiveRecord::Undo::UndoLog.find_by(id: undo_log_id)
      end

      def execute_soft_delete_cascade(class_name, record_id, undo_log, whodunnit, tenant)
        undo_log.update!(status: :processing)
        record = class_name.constantize.unscoped.find(record_id)
        timestamp = record_timestamp(record, undo_log)

        run_cascade_with_context(record, timestamp, undo_log, whodunnit, tenant)
        undo_log.update!(status: :completed)
      end

      def record_timestamp(record, undo_log)
        col = record.class.respond_to?(:undoable_column) ? record.class.undoable_column : :deleted_at
        record.public_send(col) || undo_log.created_at || Time.current
      end

      def run_cascade_with_context(record, timestamp, undo_log, whodunnit, tenant)
        with_execution_context(record, whodunnit, tenant) do
          CascadeHandler.new(record).soft_delete_associations_batched!(timestamp, undo_log)
        end
      end

      def with_execution_context(record, whodunnit, tenant)
        actor = whodunnit || record.send(:resolve_whodunnit, nil)
        ten = tenant || record.send(:resolve_tenant, nil)
        record.send(:with_whodunnit_context, actor) do
          orig = ActiveRecord::Undo.current_tenant
          ActiveRecord::Undo.current_tenant = ten if ten.present?
          yield
        ensure
          ActiveRecord::Undo.current_tenant = orig
        end
      end

      def handle_failure(undo_log, exception)
        return unless undo_log && ActiveRecord::Undo::UndoLog.exists?(undo_log.id)

        undo_log.update!(status: :failed, error_message: exception.message)
      end
    end
  end
end
