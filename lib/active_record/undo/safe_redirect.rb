# frozen_string_literal: true

require 'uri'

module ActiveRecord
  module Undo
    module SafeRedirect
      private

      def determine_redirect_path
        safe_redirect_path(params[:redirect_to]) ||
          safe_redirect_path(request.referer) ||
          resolve_fallback_path
      end

      def safe_redirect_path(path)
        return nil if invalid_path_string?(path)

        uri = URI.parse(path)
        return path if valid_relative_path?(path, uri)
        return path if valid_same_host_path?(uri)

        nil
      rescue URI::InvalidURIError
        nil
      end

      def invalid_path_string?(path)
        path.blank? || !path.is_a?(String) || path.match?(/[\r\n]/)
      end

      def valid_relative_path?(path, uri)
        uri.relative? && uri.scheme.nil? && path.start_with?('/') && !path.start_with?('//') && !path.start_with?('/\\')
      end

      def valid_same_host_path?(uri)
        %w[http https].include?(uri.scheme) &&
          uri.host == request.host &&
          (uri.port.nil? || uri.port == request.port)
      end

      def resolve_fallback_path
        cfg = ActiveRecord::Undo.config.default_redirect_path
        if cfg.respond_to?(:call)
          cfg.arity.zero? ? cfg.call : cfg.call(main_app)
        elsif cfg.present?
          cfg.to_s
        else
          default_root_path
        end
      rescue StandardError
        '/'
      end

      def default_root_path
        main_app.respond_to?(:root_path) ? main_app.root_path : '/'
      end
    end
  end
end
