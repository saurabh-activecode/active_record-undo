# lib/active_record/undo/engine.rb
# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Engine < ::Rails::Engine
      isolate_namespace ActiveRecord::Undo

      # Automatically appends gem migrations to the host application's migration path
      initializer 'active_record_undo.migrations' do |app|
        unless app.root.to_s.match?(root.to_s)
          config.paths['db/migrate'].expanded.each do |expanded_path|
            app.config.paths['db/migrate'] << expanded_path
          end
        end
      end
    end
  end
end
