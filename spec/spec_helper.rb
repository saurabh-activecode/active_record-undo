# spec/spec_helper.rb
# frozen_string_literal: true

require 'combustion'
require 'active_record'

# Initialize combustion dummy application with active_record
Combustion.path = 'spec/internal'
Combustion.initialize! :active_record

require 'rspec/rails'
require 'active_record/undo'
require_relative 'internal/app/models/models'

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
