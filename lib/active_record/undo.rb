# lib/active_record/undo.rb
# frozen_string_literal: true

begin
  require 'active_record'
rescue LoadError => e
  raise LoadError,
        'active_record-undo requires ActiveRecord. ' \
        "Please add 'activerecord' to your Gemfile. (Original error: #{e.message})"
end

require_relative 'undo/version'
require_relative 'undo/engine' if defined?(Rails::Engine)
require_relative 'undo/model_extension'
require_relative 'undo/undo_log'
require_relative 'undo/undo_log_item'

module ActiveRecord
  module Undo
    class Error < StandardError; end
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
