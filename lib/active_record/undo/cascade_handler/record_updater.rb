# lib/active_record/undo/cascade_handler/record_updater.rb
# frozen_string_literal: true

module ActiveRecord
  module Undo
    class CascadeHandler
      module RecordUpdater
        private

        def update_record_timestamps!(timestamp)
          column_name = @record.class.respond_to?(:undoable_column) ? @record.class.undoable_column : :deleted_at

          @record.update_columns(
            column_name => timestamp,
            updated_at: timestamp
          )
        end
      end
    end
  end
end
