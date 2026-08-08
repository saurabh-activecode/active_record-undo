# spec/active_record/cascade_handler_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Undo::CascadeHandler do
  let(:post) { Post.create!(title: 'Post') }
  subject { described_class.new(post) }

  describe '#associations_to_cascade' do
    it 'returns destroy and delete_all associations, but excludes nullify' do
      reflections = subject.send(:associations_to_cascade)
      names = reflections.map(&:name)

      expect(names).to include(:comments, :delete_all_comments)
      expect(names).not_to include(:likes)
    end
  end

  describe '#update_record_timestamps!' do
    it 'updates the configured delete column and updated_at directly in the database' do
      timestamp = Time.current
      subject.send(:update_record_timestamps!, timestamp)

      post.reload
      expect(post.deleted_at).to be_within(1.second).of(timestamp)
      expect(post.updated_at).to be_within(1.second).of(timestamp)
    end
  end
end
