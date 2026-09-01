# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Configuration
      attr_accessor :retention_period, :current_user_method, :current_tenant_method

      def initialize
        @retention_period = 30.days
        @current_user_method = nil
        @current_tenant_method = nil
      end
    end
  end
end
