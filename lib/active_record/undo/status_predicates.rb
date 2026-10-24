# frozen_string_literal: true

module ActiveRecord
  module Undo
    module StatusPredicates
      def soft_delete_pending?
        soft_delete_status == 'pending'
      end

      def soft_delete_processing?
        soft_delete_status == 'processing'
      end

      def soft_delete_completed?
        soft_delete_status == 'completed'
      end

      def soft_delete_failed?
        soft_delete_status == 'failed'
      end

      def restore_pending?
        restore_status == 'pending'
      end

      def restore_processing?
        restore_status == 'processing'
      end

      def restore_completed?
        restore_status == 'completed'
      end

      def restore_failed?
        restore_status == 'failed'
      end
    end
  end
end
