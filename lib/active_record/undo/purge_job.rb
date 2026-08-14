# frozen_string_literal: true

begin
  require 'active_job'
rescue LoadError
  # ActiveJob is not available
end

if defined?(ActiveJob::Base)
  module ActiveRecord
    module Undo
      class PurgeJob < ActiveJob::Base
        queue_as :default

        def perform(batch_size: 1000)
          ActiveRecord::Undo::Purger.purge_expired!(batch_size: batch_size)
        end
      end
    end
  end
end
