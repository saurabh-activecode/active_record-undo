# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Purger
      class << self
        def purge_expired!(batch_size: 1000)
          purge_expired_logs!(batch_size)
          purge_expired_records!(batch_size)
        end

        private

        def purge_expired_logs!(batch_size)
          loop do
            log_ids = UndoLog.expired.limit(batch_size).pluck(:id)
            break if log_ids.empty?

            UndoLogItem.where(undo_log_id: log_ids).delete_all
            UndoLog.where(id: log_ids).delete_all
          end
        end

        def purge_expired_records!(batch_size)
          ActiveRecord::Undo.undoable_models.each do |model|
            purge_model_expired_records!(model, batch_size)
          end
        end

        def purge_model_expired_records!(model, batch_size)
          primary_key = model.primary_key
          loop do
            expired_ids = model.expired.limit(batch_size).pluck(primary_key)
            break if expired_ids.empty?

            model.where(primary_key => expired_ids).delete_all
          end
        end
      end
    end
  end
end
