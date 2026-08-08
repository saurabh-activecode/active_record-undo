# lib/active_record/undo/cascade_handler.rb
# frozen_string_literal: true

require_relative 'cascade_handler/association_finder'
require_relative 'cascade_handler/record_updater'

module ActiveRecord
  module Undo
    class CascadeHandler
      include AssociationFinder
      include RecordUpdater

      def initialize(record)
        @record = record
      end

      def soft_delete_with_cascade!(timestamp, undo_log)
        cascade_to_associations!(timestamp, undo_log)
        update_record_timestamps!(timestamp)
        undo_log.undo_log_items.build(item: @record)
      end

      private

      def cascade_to_associations!(timestamp, undo_log)
        associations_to_cascade.each do |reflection|
          associated_records_for(reflection).each do |associated|
            cascade_to_record!(associated, reflection, timestamp, undo_log)
          end
        end
      end

      def cascade_to_record!(associated, reflection, timestamp, undo_log)
        return if associated.respond_to?(:soft_deleted?) && associated.soft_deleted?

        if associated.respond_to?(:soft_delete_cascade_internal!, true)
          associated.send(:soft_delete_cascade_internal!, timestamp, undo_log)
        elsif reflection.options[:dependent] == :destroy
          associated.destroy!
        end
      end
    end
  end
end
