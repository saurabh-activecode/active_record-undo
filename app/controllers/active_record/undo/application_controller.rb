# frozen_string_literal: true

require 'erb'

module ActiveRecord
  module Undo
    class ApplicationController < ActiveRecord::Undo.base_controller_class
      include SafeRedirect

      protect_from_forgery with: :exception, unless: -> { request.format.json? }

      rescue_from ActiveRecord::Undo::SecurityError, with: :handle_security_error

      private

      def resolve_whodunnit_user
        if respond_to?(:current_user, true) && send(:current_user).present?
          send(:current_user)
        elsif ActiveRecord::Undo.config.current_user_method.respond_to?(:call)
          ActiveRecord::Undo.config.current_user_method.call
        else
          ActiveRecord::Undo.whodunnit
        end
      end

      def resolve_current_tenant
        if respond_to?(:current_tenant, true) && send(:current_tenant).present?
          send(:current_tenant)
        elsif ActiveRecord::Undo.config.current_tenant_method.respond_to?(:call)
          ActiveRecord::Undo.config.current_tenant_method.call
        else
          ActiveRecord::Undo.current_tenant
        end
      end

      def handle_security_error(error)
        respond_to do |format|
          format.html { handle_html_error(error.message, :forbidden) }
          format.turbo_stream { render_turbo_stream_error(error.message, :forbidden) }
          format.json { render json: { error: error.message }, status: :forbidden }
        end
      end

      def handle_not_found
        msg = 'Undo log not found or already restored.'
        respond_to do |format|
          format.html { handle_html_error(msg, :not_found) }
          format.turbo_stream { render_turbo_stream_error(msg, :not_found) }
          format.json { render json: { error: msg }, status: :not_found }
        end
      end

      def handle_expired
        msg = 'Undo action has expired.'
        respond_to do |format|
          format.html { handle_html_error(msg, :unprocessable_entity) }
          format.turbo_stream { render_turbo_stream_error(msg, :unprocessable_entity) }
          format.json { render json: { error: msg }, status: :unprocessable_entity }
        end
      end

      def handle_html_error(message, status)
        if should_redirect_on_error?
          redirect_to determine_redirect_path, alert: message, status: :see_other
        else
          render plain: message, status: status
        end
      end

      def should_redirect_on_error?
        return true if ActiveRecord::Undo.config.error_handling == :redirect
        return false if ActiveRecord::Undo.config.error_handling == :render

        safe_redirect_path(params[:redirect_to]).present? || safe_redirect_path(request.referer).present?
      end

      def render_turbo_stream_error(message, status)
        render inline: turbo_stream_template('alert', message),
               content_type: 'text/vnd.turbo-stream.html',
               status: status
      end

      def turbo_stream_template(type, message)
        escaped = ERB::Util.html_escape(message)
        '<turbo-stream action="append" target="notifications"><template>' \
          "<div class=\"undo-notification undo-#{type}\">#{escaped}</div>" \
          '</template></turbo-stream>'
      end
    end
  end
end
