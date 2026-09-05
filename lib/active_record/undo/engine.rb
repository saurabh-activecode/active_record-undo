# frozen_string_literal: true

require_relative 'view_helpers'

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

      initializer 'active_record_undo.view_helpers' do
        ActiveSupport.on_load(:action_view) do
          include ActiveRecord::Undo::ViewHelpers
        end
      end

      initializer 'active_record_undo.turbo_stream_mime_type' do
        if defined?(Mime::Type) && (!defined?(Mime[:turbo_stream]) || Mime[:turbo_stream].nil?)
          Mime::Type.register 'text/vnd.turbo-stream.html', :turbo_stream
        end
      end

      rake_tasks do
        path = root.join('lib', 'tasks', 'active_record_undo_tasks.rake')
        load path if File.exist?(path)
      end
    end
  end
end
