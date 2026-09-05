# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Configuration
      attr_accessor :retention_period, :current_user_method, :current_tenant_method,
                    :base_controller, :default_redirect_path, :token_secret_key,
                    :token_expires_in, :error_handling

      def initialize
        @retention_period = 30.days
        @current_user_method = nil
        @current_tenant_method = nil
        @base_controller = '::ApplicationController'
        @default_redirect_path = ->(main_app) { main_app.respond_to?(:root_path) ? main_app.root_path : '/' }
        @token_secret_key = nil
        @token_expires_in = 24.hours
        @error_handling = :auto
      end
    end
  end
end
