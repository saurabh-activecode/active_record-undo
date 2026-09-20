# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Asynchronous Cascades and Status Helpers' do
  let!(:user) { User.create!(name: 'Tester') }
  let!(:account) { Account.create!(name: 'Test Tenant') }
  let!(:post) { Post.create!(title: 'Async Post') }
  let!(:comment_1) { post.comments.create!(body: 'Top Comment 1') }
  let!(:comment_2) { post.comments.create!(body: 'Top Comment 2') }
  let!(:reply_1) { comment_1.replies.create!(body: 'Reply to Comment 1', post: post) }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
  end

  describe '#soft_delete_later!' do
    it 'marks the root record immediately, creates a pending undo log, and enqueues SoftDeleteJob' do
      expect do
        undo_log = post.soft_delete_later!
        expect(undo_log).to be_a(ActiveRecord::Undo::UndoLog)
        expect(undo_log.status).to eq('pending')
        expect(undo_log.action).to eq('soft_delete')
        expect(undo_log.pending?).to be true
      end.to change(ActiveRecord::Undo::UndoLog, :count).by(1)
                                                        .and change(ActiveRecord::Undo::UndoLogItem, :count).by(1)

      expect(post.reload.soft_deleted?).to be true
      expect(Post.kept).not_to include(post)

      expect(ActiveRecord::Undo::SoftDeleteJob).to have_been_enqueued.with(
        'Post', post.id, post.undo_log.id, whodunnit: nil, tenant: nil
      )
    end

    it 'supports custom queue option when enqueuing' do
      post.soft_delete_later!(queue: :low_priority)
      expect(ActiveRecord::Undo::SoftDeleteJob).to have_been_enqueued.on_queue('low_priority')
    end

    it 'sets undoable? to false while soft delete is pending' do
      post.soft_delete_later!
      expect(post.reload.undoable?).to be false
    end
  end

  describe 'ActiveRecord::Undo::SoftDeleteJob' do
    it 'transitions status through pending -> processing -> completed and captures all descendants' do
      undo_log = post.soft_delete_later!
      expect(undo_log.status).to eq('pending')

      perform_enqueued_jobs

      undo_log.reload
      expect(undo_log.status).to eq('completed')
      expect(undo_log.completed?).to be true
      expect(post.reload.undoable?).to be true

      expect(comment_1.reload.soft_deleted?).to be true
      expect(comment_2.reload.soft_deleted?).to be true
      expect(reply_1.reload.soft_deleted?).to be true

      expect(undo_log.undo_log_items.count).to eq(4)
      item_records = undo_log.undo_log_items.map(&:item)
      expect(item_records).to include(post, comment_1, comment_2, reply_1)
    end

    it 'handles errors by marking undo_log as failed and saving error_message' do
      undo_log = post.soft_delete_later!

      allow_any_instance_of(ActiveRecord::Undo::CascadeHandler).to receive(:soft_delete_associations_batched!)
        .and_raise(StandardError, 'Database disk failure')

      expect do
        perform_enqueued_jobs
      end.to raise_error(StandardError, 'Database disk failure')

      undo_log.reload
      expect(undo_log.status).to eq('failed')
      expect(undo_log.failed?).to be true
      expect(undo_log.error_message).to eq('Database disk failure')
      expect(post.reload.undoable?).to be false
    end

    it 'processes deep association hierarchies in batches' do
      10.times do |i|
        c = post.comments.create!(body: "Bulk comment #{i}")
        c.replies.create!(body: "Bulk reply #{i}", post: post)
      end

      undo_log = post.soft_delete_later!
      perform_enqueued_jobs

      expect(undo_log.reload.completed?).to be true
      expect(undo_log.undo_log_items.count).to eq(24) # 1 post + 2 original comments + 1 original reply + 20 new
    end
  end

  describe '#restore_later!' do
    before do
      post.soft_delete_later!
      perform_enqueued_jobs
      post.reload
    end

    it 'enqueues RestoreJob and transitions log status to pending' do
      undo_log = post.undo_log
      expect(undo_log.completed?).to be true

      result_log = post.restore_later!
      expect(result_log.id).to eq(undo_log.id)
      expect(result_log.status).to eq('pending')
      expect(result_log.action).to eq('restore')

      expect(ActiveRecord::Undo::RestoreJob).to have_been_enqueued.with(undo_log.id, whodunnit: nil)
    end

    it 'allows calling restore_later! directly on UndoLog' do
      undo_log = post.undo_log
      result = undo_log.restore_later!(queue: :critical)

      expect(result.status).to eq('pending')
      expect(ActiveRecord::Undo::RestoreJob).to have_been_enqueued
        .with(undo_log.id, whodunnit: nil).on_queue('critical')
    end

    it 'prevents concurrent restore when log is already pending or processing' do
      undo_log = post.undo_log
      undo_log.restore_later!

      expect do
        post.restore_later!
      end.to raise_error(ActiveRecord::Undo::Error, /already scheduled for restore/)

      undo_log.update_columns(status: 1) # processing
      expect do
        post.restore_later!
      end.to raise_error(ActiveRecord::Undo::Error, /currently processing/)
    end
  end

  describe 'ActiveRecord::Undo::RestoreJob' do
    before do
      post.soft_delete_later!
      perform_enqueued_jobs
      post.reload
    end

    it 'restores associations bottom-up and cleans up undo log on completion' do
      restored_order = []
      allow_any_instance_of(ActiveRecord::Undo::UndoLogItem).to receive(:restore_item!).and_wrap_original do |m|
        item = m.receiver.item
        restored_order << "#{item.class.name}:#{item.id}"
        m.call
      end

      undo_log = post.undo_log
      log_id = undo_log.id
      undo_log.restore_later!

      perform_enqueued_jobs

      expect(post.reload.soft_deleted?).to be false
      expect(comment_1.reload.soft_deleted?).to be false
      expect(comment_2.reload.soft_deleted?).to be false
      expect(reply_1.reload.soft_deleted?).to be false

      # Verify bottom-up order: replies and comments restored before post
      post_index = restored_order.index("Post:#{post.id}")
      reply_index = restored_order.index("Comment:#{reply_1.id}")
      expect(reply_index).to be < post_index

      # Log is destroyed upon successful restoration
      expect(ActiveRecord::Undo::UndoLog.find_by(id: log_id)).to be_nil
    end

    it 'records failure and error_message when an exception occurs during restore' do
      undo_log = post.undo_log
      allow_any_instance_of(ActiveRecord::Undo::UndoLogItem).to receive(:restore_item!)
        .and_raise(StandardError, 'Restore serialization error')

      undo_log.restore_later!

      expect do
        perform_enqueued_jobs
      end.to raise_error(StandardError, 'Restore serialization error')

      undo_log.reload
      expect(undo_log.status).to eq('failed')
      expect(undo_log.failed?).to be true
      expect(undo_log.error_message).to eq('Restore serialization error')
    end
  end

  describe 'Frontend Status Helpers' do
    describe 'on UndoLog' do
      let(:log) { ActiveRecord::Undo::UndoLog.create!(action: :soft_delete, status: :pending) }

      it 'returns soft_delete_status correctly' do
        expect(log.soft_delete_status).to eq('pending')
        expect(log.soft_delete_pending?).to be true
        expect(log.restore_status).to be_nil

        log.update!(status: :processing)
        expect(log.soft_delete_status).to eq('processing')
        expect(log.soft_delete_processing?).to be true

        log.update!(status: :completed)
        expect(log.soft_delete_status).to eq('completed')
        expect(log.soft_delete_completed?).to be true

        log.update!(status: :failed)
        expect(log.soft_delete_status).to eq('failed')
        expect(log.soft_delete_failed?).to be true
      end

      it 'returns restore_status correctly' do
        log.update!(action: :restore, status: :pending)
        expect(log.soft_delete_status).to eq('completed')
        expect(log.restore_status).to eq('pending')
        expect(log.restore_pending?).to be true

        log.update!(status: :processing)
        expect(log.restore_status).to eq('processing')
        expect(log.restore_processing?).to be true

        log.update!(status: :failed)
        expect(log.restore_status).to eq('failed')
        expect(log.restore_failed?).to be true
      end
    end

    describe 'on Model' do
      it 'tracks status through soft delete lifecycle' do
        expect(post.soft_delete_status).to be_nil
        expect(post.restore_status).to be_nil

        log = post.soft_delete_later!
        expect(post.soft_delete_status).to eq('pending')
        expect(post.soft_delete_pending?).to be true

        log.update!(status: :processing)
        expect(post.soft_delete_status).to eq('processing')
        expect(post.soft_delete_processing?).to be true

        log.update!(status: :completed)
        expect(post.soft_delete_status).to eq('completed')
        expect(post.soft_delete_completed?).to be true
      end

      it 'tracks status through restore lifecycle' do
        post.soft_delete_later!
        perform_enqueued_jobs
        expect(post.soft_delete_status).to eq('completed')

        log = post.restore_later!
        expect(post.restore_status).to eq('pending')
        expect(post.restore_pending?).to be true
        expect(post.soft_delete_status).to eq('completed')

        log.update!(status: :processing)
        expect(post.restore_status).to eq('processing')
        expect(post.restore_processing?).to be true

        log.update!(status: :failed)
        expect(post.restore_status).to eq('failed')
        expect(post.restore_failed?).to be true
      end
    end
  end

  describe 'ViewHelpers status badges' do
    include ActiveRecord::Undo::ViewHelpers

    it 'renders badge with appropriate classes for model and log' do
      log = ActiveRecord::Undo::UndoLog.create!(action: :soft_delete, status: :processing)
      badge = undo_status_badge(log)
      expect(badge).to include('undo-status-badge')
      expect(badge).to include('undo-soft-delete-badge')
      expect(badge).to include('undo-status-processing')
      expect(badge).to include('Processing')

      post.soft_delete_later!
      model_badge = undo_status_badge(post)
      expect(model_badge).to include('undo-status-badge')
      expect(model_badge).to include('undo-soft-delete-badge')
      expect(model_badge).to include('undo-status-pending')

      sd_badge = soft_delete_status_badge(post, text: 'Deleting...')
      expect(sd_badge).to include('undo-soft-delete-badge')
      expect(sd_badge).to include('Deleting...')

      res_badge = restore_status_badge(post)
      expect(res_badge).to be_nil
    end
  end
end
