# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Configuration
      attr_accessor :retention_period

      def initialize
        @retention_period = 30.days
      end
    end
  end
end
