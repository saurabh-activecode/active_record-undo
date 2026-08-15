# lib/active_record/undo.rb
# frozen_string_literal: true

begin
  require 'active_record'
rescue LoadError => e
  raise LoadError,
        'active_record-undo requires ActiveRecord. ' \
        "Please add 'activerecord' to your Gemfile. (Original error: #{e.message})"
end

require 'set'
require_relative 'undo/version'
require_relative 'undo/engine' if defined?(Rails::Engine)
require_relative 'undo/configuration'
require_relative 'undo/model_extension'
require_relative 'undo/undo_log'
require_relative 'undo/undo_log_item'
require_relative 'undo/purger'
require_relative 'undo/purge_job'

module ActiveRecord
  module Undo
    class Error < StandardError; end

    class << self
      def config
        @config ||= Configuration.new
      end

      def configure
        yield(config)
      end

      def registered_models
        @registered_models ||= Set.new
      end

      def undoable_models
        eager_load_rails!
        models = registered_models.to_a
        if defined?(ActiveRecord::Base)
          models += ActiveRecord::Base.descendants.select { |m| m.respond_to?(:undoable_column) }
        end
        models.uniq
      end

      private

      def eager_load_rails!
        return unless defined?(Rails) && Rails.application

        Rails.application.eager_load!
      rescue StandardError
        # Safe fallback if Rails eager loading fails in test environments
      end
    end
  end
end

if defined?(ActiveSupport)
  ActiveSupport.on_load(:active_record) do
    include ActiveRecord::Undo::ModelExtension
  end
elsif defined?(ActiveRecord::Base)
  # Fallback for bare Ruby scripts where ActiveSupport hooks aren't initialized yet
  ActiveRecord::Base.include(ActiveRecord::Undo::ModelExtension)
end
