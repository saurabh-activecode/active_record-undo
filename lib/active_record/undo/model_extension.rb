# lib/active_record/undo/model_extension.rb
# frozen_string_literal: true

require_relative 'cascade_handler'

module ActiveRecord
  module Undo
    module ModelExtension
      extend ActiveSupport::Concern

      class_methods do
        # Accept a custom column parameter, defaulting to :deleted_at
        def acts_as_undoable(column: :deleted_at)
          include InstanceMethods

          class_attribute :undoable_column
          self.undoable_column = column.to_sym

          # Dynamic scopes using the configured column
          scope :kept, -> { where(undoable_column => nil) }
          scope :soft_deleted, -> { where.not(undoable_column => nil) }
        end
      end

      module InstanceMethods
        def soft_deleted?
          public_send(self.class.undoable_column).present?
        end

        def undoable?
          return false unless soft_deleted?

          ActiveRecord::Undo::UndoLogItem.joins(:undo_log).exists?(
            item_type: self.class.name,
            item_id: id
          )
        end

        def soft_delete!
          ensure_undoable_column_exists!
          return false if soft_deleted?

          undo_log = nil
          timestamp = Time.current

          transaction do
            undo_log = ActiveRecord::Undo::UndoLog.create!
            soft_delete_cascade_internal!(timestamp, undo_log)
            undo_log.save!
          end

          undo_log
        end

        def restore!
          ensure_undoable_column_exists!
          return false unless soft_deleted?

          log_item = find_latest_undo_log_item

          if log_item
            log_item.undo_log.restore!
          else
            column_name = self.class.undoable_column
            update_columns(column_name => nil, updated_at: Time.current)
            true
          end
        end

        private

        def ensure_undoable_column_exists!
          column_name = self.class.undoable_column
          return if self.class.column_names.include?(column_name.to_s)

          raise ActiveRecord::Undo::Error,
                "The configured soft-delete column '#{column_name}' " \
                "does not exist on table '#{self.class.table_name}'."
        end

        def find_latest_undo_log_item
          ActiveRecord::Undo::UndoLogItem
            .where(item: self)
            .order(created_at: :desc)
            .first
        end

        def soft_delete_cascade_internal!(timestamp, undo_log)
          CascadeHandler.new(self).soft_delete_with_cascade!(timestamp, undo_log)
        end
      end
    end
  end
end
