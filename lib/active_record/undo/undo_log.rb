# frozen_string_literal: true

require 'active_support/message_verifier'

module ActiveRecord
  module Undo
    class UndoLog < ActiveRecord::Base
      self.table_name = 'undo_logs'

      include ModelExtension::AttributionHelper
      include ModelExtension::TenantVerification

      has_many :undo_log_items, class_name: 'ActiveRecord::Undo::UndoLogItem', dependent: :destroy

      belongs_to :whodunnit, polymorphic: true, optional: true
      belongs_to :tenant, polymorphic: true, optional: true

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

      def self.find_by_signed_token(token, purpose: :restore)
        return nil if token.blank?

        verified_id = verify_signed_token(token, purpose: purpose)
        return nil unless verified_id

        find_by(id: verified_id)
      rescue StandardError
        nil
      end

      def self.verify_signed_token(token, purpose: :restore)
        token_verifier.verified(token, purpose: purpose)
      rescue ActiveSupport::MessageVerifier::InvalidSignature
        nil
      end

      def self.token_verifier
        if defined?(Rails.application) && Rails.application.respond_to?(:message_verifier)
          Rails.application.message_verifier(:active_record_undo)
        else
          key = ActiveRecord::Undo.config.token_secret_key || 'active_record_undo_default_secret_key_32_bytes'
          @token_verifier ||= ActiveSupport::MessageVerifier.new(key, digest: 'SHA256')
        end
      end

      def expired?
        period = ActiveRecord::Undo.config.retention_period
        return false unless period && created_at

        created_at < Time.current - period
      end

      def signed_token(expires_in: ActiveRecord::Undo.config.token_expires_in, purpose: :restore)
        self.class.token_verifier.generate(id, purpose: purpose, expires_in: expires_in)
      end
      alias to_signed_token signed_token

      # Restores all records associated with this deletion batch
      def restore!(whodunnit: nil)
        ActiveRecord::Undo.verify_configured_context!
        verify_tenant_match!(self) if tenant_present?

        actor = resolve_whodunnit(whodunnit)
        with_whodunnit_context(actor) do
          execute_restore_transaction!
        end
      end

      private

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
