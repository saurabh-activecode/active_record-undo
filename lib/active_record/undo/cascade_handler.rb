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

      def soft_delete_associations_batched!(timestamp, undo_log, batch_size: 1000)
        associations_to_cascade.each do |reflection|
          cascade_association_batched!(reflection, timestamp, undo_log, batch_size)
        end
      end

      private

      def cascade_association_batched!(reflection, timestamp, undo_log, batch_size)
        target = @record.public_send(reflection.name)
        return if target.nil?

        if reflection.collection? || target.is_a?(ActiveRecord::Relation)
          cascade_collection_batched!(target, reflection, timestamp, undo_log, batch_size)
        else
          cascade_record_batched!(target, reflection, timestamp, undo_log, batch_size)
        end
      end

      def cascade_collection_batched!(target, reflection, timestamp, undo_log, batch_size)
        each_collection_batch(target, batch_size) do |batch|
          batch.each do |associated|
            cascade_record_batched!(associated, reflection, timestamp, undo_log, batch_size)
          end
        end
      end

      def each_collection_batch(target, batch_size, &)
        if target.respond_to?(:in_batches)
          target.in_batches(of: batch_size, &)
        else
          target.each_slice(batch_size, &)
        end
      end

      def cascade_record_batched!(associated, reflection, timestamp, undo_log, batch_size)
        return if skip_cascade?(associated)

        if undoable_record?(associated)
          process_undoable_child!(associated, timestamp, undo_log, batch_size)
        elsif reflection.options[:dependent] == :destroy
          associated.destroy!
        end
      end

      def skip_cascade?(associated)
        return true if associated.nil?
        return true if associated.respond_to?(:soft_deleted?) && associated.soft_deleted?

        if associated.respond_to?(:soft_deleted?) && associated.persisted?
          associated.reload
          return true if associated.soft_deleted?
        end

        false
      end

      def undoable_record?(associated)
        associated.respond_to?(:acts_as_undoable) || associated.class.respond_to?(:undoable_column)
      end

      def process_undoable_child!(associated, timestamp, undo_log, batch_size)
        self.class.new(associated).soft_delete_associations_batched!(timestamp, undo_log, batch_size: batch_size)
        column_name = associated.class.respond_to?(:undoable_column) ? associated.class.undoable_column : :deleted_at
        associated.update_columns(column_name => timestamp, updated_at: timestamp)
        ActiveRecord::Undo::UndoLogItem.create!(undo_log_id: undo_log.id, item: associated)
      end

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
