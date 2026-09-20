# frozen_string_literal: true

require 'active_support/message_verifier'

module ActiveRecord
  module Undo
    class UndoLog < ActiveRecord::Base
      module TokenVerifier
        extend ActiveSupport::Concern

        class_methods do
          def find_by_signed_token(token, purpose: :restore)
            return nil unless token.is_a?(String) && token.present?

            verified_id = verify_signed_token(token, purpose: purpose)
            return nil unless verified_id

            find_by(id: verified_id)
          rescue StandardError
            nil
          end

          def verify_signed_token(token, purpose: :restore)
            return nil unless token.is_a?(String) && token.present?

            token_verifier.verified(token, purpose: purpose)
          rescue StandardError
            nil
          end

          def token_verifier
            if defined?(Rails.application) && Rails.application.respond_to?(:message_verifier)
              Rails.application.message_verifier(:active_record_undo)
            else
              key = ActiveRecord::Undo.config.token_secret_key || 'active_record_undo_default_secret_key_32_bytes'
              @token_verifier ||= ActiveSupport::MessageVerifier.new(key, digest: 'SHA256')
            end
          end
        end

        def signed_token(expires_in: ActiveRecord::Undo.config.token_expires_in, purpose: :restore)
          self.class.token_verifier.generate(id, purpose: purpose, expires_in: expires_in)
        end
        alias to_signed_token signed_token
      end
    end
  end
end
