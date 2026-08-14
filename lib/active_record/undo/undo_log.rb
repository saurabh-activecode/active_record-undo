# lib/active_record/undo/undo_log.rb
# frozen_string_literal: true

module ActiveRecord
  module Undo
    class UndoLog < ActiveRecord::Base
      self.table_name = 'undo_logs'

      has_many :undo_log_items, class_name: 'ActiveRecord::Undo::UndoLogItem', dependent: :destroy

      scope :expired, lambda {
        period = ActiveRecord::Undo.config.retention_period
        if period
          where('created_at < ?', Time.current - period)
        else
          none
        end
      }

      # Restores all records associated with this deletion batch
      def restore!
        transaction do
          # Reverse order ensures child records are restored before or after parents as needed
          undo_log_items.reverse_each(&:restore_item!)
          destroy! # Clean up log after successful restoration
        end
      end
    end
  end
end
