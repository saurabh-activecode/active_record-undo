# frozen_string_literal: true

module ActiveRecord
  module Undo
    module ViewHelpers
      def undo_button_to(target, text = nil, signed: false, **html_options)
        btn_text = extract_undo_text(text, html_options)
        url = resolve_undo_path(target, signed: signed)
        button_to(btn_text, url, method: :post, **html_options)
      end

      def undo_link_to(target, text = nil, signed: false, **html_options)
        link_text = extract_undo_text(text, html_options)
        url = resolve_undo_path(target, signed: signed)
        data = { turbo_method: :post }.merge(html_options.delete(:data) || {})
        link_to(link_text, url, method: :post, data: data, **html_options)
      end

      private

      def extract_undo_text(text, html_options)
        text || html_options.delete(:text) || 'Undo'
      end

      def resolve_undo_path(target, signed: false)
        router = undo_engine_router
        if signed
          token = extract_signed_token(target)
          router.signed_restore_path(token: token)
        else
          router.restore_log_path(extract_log_target(target))
        end
      end

      def extract_signed_token(target)
        if target.is_a?(String)
          target
        elsif target.respond_to?(:signed_token)
          target.signed_token
        elsif target.respond_to?(:undo_log) && target.undo_log
          target.undo_log.signed_token
        else
          raise ArgumentError, "Cannot generate signed token for #{target.inspect}"
        end
      end

      def extract_log_target(target)
        if target.respond_to?(:undo_log) && target.undo_log
          target.undo_log
        else
          target
        end
      end

      def undo_engine_router
        if respond_to?(:active_record_undo)
          active_record_undo
        elsif defined?(main_app) && main_app.respond_to?(:active_record_undo)
          main_app.active_record_undo
        elsif respond_to?(:restore_log_path)
          self
        else
          ActiveRecord::Undo::Engine.routes.url_helpers
        end
      end
    end
  end
end
