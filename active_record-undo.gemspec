# frozen_string_literal: true

require_relative 'lib/active_record/undo/version'

Gem::Specification.new do |spec|
  spec.name = 'active_record-undo'
  spec.version = ActiveRecord::Undo::VERSION
  spec.authors = ['Saurabh Sharma']
  spec.email = ['saurabh@activecode.in']

  spec.summary = 'Soft-delete extension for ActiveRecord with transactional cascade undo tracking.'
  spec.description = 'Provides soft deletion and automatic restoration of records and their dependent associations.'
  spec.homepage = 'https://github.com/saurabh-activecode/active_record-undo'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.1.0'

  # spec.metadata["allowed_push_host"] = "TODO: Set to your gem server 'https://example.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'
  # spec.metadata["source_code_uri"] = "TODO: Put your gem's public repo URL here."
  # spec.metadata["changelog_uri"] = "TODO: Put your gem's CHANGELOG.md URL here."

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime Dependencies
  spec.add_dependency 'activerecord', '>= 7.0.0'

  # Development Dependencies
  spec.add_development_dependency 'bundler', '~> 2.0'
  spec.add_development_dependency 'combustion', '~> 1.3'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.0'
  spec.add_development_dependency 'rspec-rails'
  spec.add_development_dependency 'rubocop', '~> 1.21'
  spec.add_development_dependency 'sqlite3', '>= 1.4'
end
