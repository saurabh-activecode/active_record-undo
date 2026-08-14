# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Undo::Purger do
  let!(:original_retention_period) { ActiveRecord::Undo.config.retention_period }

  after do
    ActiveRecord::Undo.config.retention_period = original_retention_period
  end

  describe '.purge_expired!' do
    context 'with global retention period' do
      before do
        ActiveRecord::Undo.config.retention_period = 30.days
      end

      it 'purges records and logs past the retention window, but preserves those within it' do
        # Record 1: Deleted 40 days ago (past 30 days retention window) -> should be purged
        post_expired = Post.create!(title: 'Expired Post')
        log_expired = post_expired.soft_delete!
        post_expired.update_columns(deleted_at: 40.days.ago)
        log_expired.update_columns(created_at: 40.days.ago)

        # Record 2: Deleted 10 days ago (within 30 days retention window) -> should be preserved
        post_active = Post.create!(title: 'Active Post')
        log_active = post_active.soft_delete!
        post_active.update_columns(deleted_at: 10.days.ago)
        log_active.update_columns(created_at: 10.days.ago)

        # Before purging
        expect(Post.soft_deleted.count).to eq(2)
        expect(ActiveRecord::Undo::UndoLog.count).to eq(2)
        expect(ActiveRecord::Undo::UndoLogItem.count).to eq(2)

        # Run purger
        ActiveRecord::Undo::Purger.purge_expired!

        # After purging
        expect(Post.exists?(post_expired.id)).to be false
        expect(ActiveRecord::Undo::UndoLog.exists?(log_expired.id)).to be false
        expect(ActiveRecord::Undo::UndoLogItem.where(undo_log_id: log_expired.id).exists?).to be false

        expect(Post.exists?(post_active.id)).to be true
        expect(ActiveRecord::Undo::UndoLog.exists?(log_active.id)).to be true
        expect(ActiveRecord::Undo::UndoLogItem.where(undo_log_id: log_active.id).exists?).to be true
      end

      it 'purges both parent and cascading child records at the same time, leaving no orphans' do
        post = Post.create!(title: 'Orphan Prevention Test Post')
        comment = Comment.create!(body: 'Child Comment', post: post)

        # Soft delete post, cascading to comment
        log = post.soft_delete!

        # Set deletion timestamp to be expired
        post.update_columns(deleted_at: 40.days.ago)
        comment.update_columns(deleted_at: 40.days.ago)
        log.update_columns(created_at: 40.days.ago)

        # Verify they exist as soft-deleted before purging
        expect(Post.soft_deleted.count).to eq(1)
        expect(Comment.soft_deleted.count).to eq(1)

        # Run purger
        ActiveRecord::Undo::Purger.purge_expired!

        # Verify parent and children are hard-deleted
        expect(Post.exists?(post.id)).to be false
        expect(Comment.exists?(comment.id)).to be false

        # Verify no comments pointing to the post exist in the table (no orphans)
        expect(Comment.unscoped.where(post_id: post.id).count).to eq(0)
      end
    end

    context 'when retention period is nil' do
      before do
        ActiveRecord::Undo.config.retention_period = nil
      end

      it 'does not purge any records or logs' do
        post = Post.create!(title: 'Post')
        log = post.soft_delete!
        post.update_columns(deleted_at: 100.days.ago)
        log.update_columns(created_at: 100.days.ago)

        ActiveRecord::Undo::Purger.purge_expired!

        expect(Post.exists?(post.id)).to be true
        expect(ActiveRecord::Undo::UndoLog.exists?(log.id)).to be true
      end
    end

    context 'with batch_size specification' do
      before do
        ActiveRecord::Undo.config.retention_period = 30.days
      end

      it 'purges in batches' do
        # Create 3 expired posts
        posts = Array.new(3) do |i|
          p = Post.create!(title: "Expired Post #{i}")
          log = p.soft_delete!
          p.update_columns(deleted_at: 40.days.ago)
          log.update_columns(created_at: 40.days.ago)
          p
        end

        # Run purger with batch_size of 1
        ActiveRecord::Undo::Purger.purge_expired!(batch_size: 1)

        posts.each do |p|
          expect(Post.exists?(p.id)).to be false
        end
        expect(ActiveRecord::Undo::UndoLog.count).to eq(0)
      end
    end
  end

  describe 'expired scope and predicate' do
    before do
      ActiveRecord::Undo.config.retention_period = 10.days
    end

    it 'correctly filters expired records and reports expired status' do
      post_expired = Post.create!(title: 'Expired Post')
      post_expired.soft_delete!
      post_expired.update_columns(deleted_at: 15.days.ago)

      post_active = Post.create!(title: 'Active Post')
      post_active.soft_delete!
      post_active.update_columns(deleted_at: 5.days.ago)

      post_kept = Post.create!(title: 'Kept Post')

      # Check scopes
      expect(Post.expired).to include(post_expired)
      expect(Post.expired).not_to include(post_active)
      expect(Post.expired).not_to include(post_kept)

      # Check instance predicate
      expect(post_expired.expired?).to be true
      expect(post_active.expired?).to be false
      expect(post_kept.expired?).to be false
    end
  end

  describe 'Rake task active_record_undo:purge_expired' do
    before :all do
      require 'rake'
      Rake.application = Rake::Application.new
      task_path = File.expand_path('../../../lib/active_record/undo/tasks/purge.rake', __dir__)
      load task_path
      Rake::Task.define_task(:environment)
    end

    before do
      Rake::Task['active_record_undo:purge_expired'].reenable
    end

    it 'calls Purger.purge_expired! with default batch size' do
      expect(ActiveRecord::Undo::Purger).to receive(:purge_expired!).with(batch_size: 1000)
      Rake::Task['active_record_undo:purge_expired'].invoke
    end

    it 'calls Purger.purge_expired! with custom batch size from ENV' do
      stub_const('ENV', ENV.to_h.merge('BATCH_SIZE' => '500'))
      expect(ActiveRecord::Undo::Purger).to receive(:purge_expired!).with(batch_size: 500)
      Rake::Task['active_record_undo:purge_expired'].invoke
    end
  end

  if defined?(ActiveRecord::Undo::PurgeJob)
    describe ActiveRecord::Undo::PurgeJob do
      it 'delegates to Purger.purge_expired!' do
        expect(ActiveRecord::Undo::Purger).to receive(:purge_expired!).with(batch_size: 1000)
        ActiveRecord::Undo::PurgeJob.perform_now
      end
    end
  end
end
