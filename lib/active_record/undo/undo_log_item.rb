# lib/active_record/undo/undo_log_item.rb
# frozen_string_literal: true

module ActiveRecord
  module Undo
    class UndoLogItem < ActiveRecord::Base
      self.table_name = 'undo_log_items'

      belongs_to :undo_log, class_name: 'ActiveRecord::Undo::UndoLog'
      belongs_to :item, polymorphic: true

      def restore_item!
        klass = resolve_model_class
        target = klass.unscoped.find_by(id: item_id)
        return unless target

        column_name = klass.respond_to?(:undoable_column) ? klass.undoable_column : :deleted_at
        ensure_column_exists!(klass, column_name)

        return unless target.public_send(column_name).present?

        reset_soft_delete_column!(target, column_name)
      end

      private

      def resolve_model_class
        klass = item_type.constantize
        unless klass.is_a?(Class) && klass < ActiveRecord::Base
          raise ActiveRecord::Undo::Error,
                "Cannot restore item: '#{item_type}' is not an ActiveRecord model."
        end

        klass
      rescue NameError => e
        raise ActiveRecord::Undo::Error,
              "Cannot restore item: model class '#{item_type}' could not be loaded. " \
              "Original error: #{e.message}"
      end

      def ensure_column_exists!(klass, column_name)
        return if klass.column_names.include?(column_name.to_s)

        raise ActiveRecord::Undo::Error,
              "Cannot restore item: column '#{column_name}' does not exist on '#{item_type}' model."
      end

      def reset_soft_delete_column!(target, column_name)
        target.update_columns(
          column_name => nil,
          updated_at: Time.current
        )
      end
    end
  end
end
