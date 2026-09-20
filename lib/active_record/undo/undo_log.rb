# frozen_string_literal: true

require_relative 'undo_log/token_verifier'

module ActiveRecord
  module Undo
    class UndoLog < ActiveRecord::Base
      self.table_name = 'undo_logs'

      include ModelExtension::AttributionHelper
      include ModelExtension::TenantVerification
      include TokenVerifier
      include StatusPredicates

      has_many :undo_log_items, class_name: 'ActiveRecord::Undo::UndoLogItem', dependent: :destroy

      belongs_to :whodunnit, polymorphic: true, optional: true
      belongs_to :tenant, polymorphic: true, optional: true

      enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }, default: :completed
      enum :action, { soft_delete: 0, restore: 1 }, default: :soft_delete

      scope :for_whodunnit, lambda { |user|
        if user.is_a?(ActiveRecord::Base)
          where(whodunnit: user)
        else
          where(whodunnit_id: user)
        end
      }

      scope :for_tenant, lambda { |tenant|
        if tenant.is_a?(ActiveRecord::Base)
          where(tenant: tenant)
        else
          where(tenant_id: tenant)
        end
      }

      scope :expired, lambda {
        period = ActiveRecord::Undo.config.retention_period
        if period
          where('created_at < ?', Time.current - period)
        else
          none
        end
      }

      def expired?
        period = ActiveRecord::Undo.config.retention_period
        return false unless period && created_at

        created_at < Time.current - period
      end

      def soft_delete_status
        return status if action == 'soft_delete' || action.nil?

        'completed'
      end

      def restore_status
        return status if action == 'restore'

        nil
      end

      def restore_later!(whodunnit: nil, queue: nil)
        verify_restore_preconditions!
        with_lock do
          validate_restore_status_eligibility!
          update!(action: :restore, status: :pending)
        end
        enqueue_restore_job!(whodunnit, queue)
        self
      end

      # Restores all records associated with this deletion batch
      def restore!(whodunnit: nil)
        verify_restore_preconditions!
        validate_restore_status_eligibility!

        actor = resolve_whodunnit(whodunnit)
        with_whodunnit_context(actor) do
          execute_restore_transaction!
        end
      end

      private

      def verify_restore_preconditions!
        ActiveRecord::Undo.verify_configured_context!
        verify_tenant_match!(self) if tenant_present?
        raise ActiveRecord::Undo::Error, 'Undo action has expired.' if expired?
      end

      def validate_restore_status_eligibility!
        raise ActiveRecord::Undo::Error, 'Cannot restore: UndoLog is currently processing.' if processing?

        if pending? && action == 'restore'
          raise ActiveRecord::Undo::Error, 'Cannot restore: UndoLog is already scheduled for restore.'
        end
        return if completed?

        raise ActiveRecord::Undo::Error, "Cannot restore: UndoLog is not completed (current status: #{status})."
      end

      def enqueue_restore_job!(whodunnit, queue)
        job_class = ActiveRecord::Undo::RestoreJob
        job = queue.present? ? job_class.set(queue: queue) : job_class
        job.perform_later(id, whodunnit: whodunnit)
      end

      def tenant_present?
        tenant_id.present? || tenant_type.present?
      end

      def execute_restore_transaction!
        transaction do
          # Reverse order ensures child records are restored before or after parents as needed
          undo_log_items.reverse_each(&:restore_item!)
          destroy! # Clean up log after successful restoration
        end
      end
    end
  end
end
