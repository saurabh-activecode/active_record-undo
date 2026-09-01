# frozen_string_literal: true

namespace :active_record_undo do
  desc 'Purge expired soft-deleted records and undo logs'
  task purge_expired: :environment do
    batch_size = ENV['BATCH_SIZE'] ? ENV['BATCH_SIZE'].to_i : 1000
    ActiveRecord::Undo::Purger.purge_expired!(batch_size: batch_size)
  end
end
