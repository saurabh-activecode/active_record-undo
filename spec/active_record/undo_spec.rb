# spec/active_record/undo_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Undo do
  describe '.acts_as_undoable' do
    it 'sets default undoable_column to :deleted_at' do
      expect(Post.undoable_column).to eq(:deleted_at)
    end

    it 'allows setting a custom column name' do
      expect(ArchiveItem.undoable_column).to eq(:archived_at)
    end
  end

  describe 'scopes' do
    let!(:active_post) { Post.create!(title: 'Active Post') }
    let!(:deleted_post) { Post.create!(title: 'Deleted Post', deleted_at: Time.current) }

    describe '.kept' do
      it 'returns only non-deleted records' do
        expect(Post.kept).to include(active_post)
        expect(Post.kept).not_to include(deleted_post)
      end
    end

    describe '.soft_deleted' do
      it 'returns only soft deleted records' do
        expect(Post.soft_deleted).to include(deleted_post)
        expect(Post.soft_deleted).not_to include(active_post)
      end
    end
  end

  describe '#soft_deleted?' do
    it 'returns false for active records' do
      post = Post.create!(title: 'Active')
      expect(post.soft_deleted?).to be false
    end

    it 'returns true for soft deleted records' do
      post = Post.create!(title: 'Deleted', deleted_at: Time.current)
      expect(post.soft_deleted?).to be true
    end

    it 'works with custom columns' do
      item = ArchiveItem.create!(name: 'Item', archived_at: Time.current)
      expect(item.soft_deleted?).to be true
    end
  end

  describe '#soft_delete!' do
    let!(:post) { Post.create!(title: 'Ruby Post') }
    let!(:comment_1) { post.comments.create!(body: 'First comment') }
    let!(:comment_2) { post.comments.create!(body: 'Second comment') }

    it 'returns false if already soft deleted' do
      post.soft_delete!
      expect(post.soft_delete!).to be false
    end

    it 'soft deletes the target record and sets deleted_at timestamp' do
      expect { post.soft_delete! }.to change { post.reload.soft_deleted? }.from(false).to(true)
    end

    it 'cascades soft deletion to dependent associations' do
      post.soft_delete!

      expect(comment_1.reload.soft_deleted?).to be true
      expect(comment_2.reload.soft_deleted?).to be true
    end

    it 'sets exactly the same soft_delete timestamp for the parent and all cascaded children' do
      post.soft_delete!

      parent_timestamp = post.reload.deleted_at
      comment_1_timestamp = comment_1.reload.deleted_at
      comment_2_timestamp = comment_2.reload.deleted_at

      expect(parent_timestamp).to be_present
      expect(comment_1_timestamp).to eq(parent_timestamp)
      expect(comment_2_timestamp).to eq(parent_timestamp)
    end

    it 'creates an UndoLog with UndoLogItems for all affected records' do
      expect do
        post.soft_delete!
      end.to change(ActiveRecord::Undo::UndoLog, :count).by(1)
                                                        .and change(ActiveRecord::Undo::UndoLogItem, :count).by(3)
    end

    it 'saves the correct values in UndoLog and UndoLogItems' do
      undo_log = post.soft_delete!

      expect(undo_log).to be_a(ActiveRecord::Undo::UndoLog)

      log_items = undo_log.undo_log_items
      expect(log_items.count).to eq(3)

      # Check that log items point to the correct associated items and have correct attributes
      expect(log_items.map(&:item)).to contain_exactly(post, comment_1, comment_2)
      expect(log_items.map(&:item_type)).to contain_exactly('Post', 'Comment', 'Comment')
      expect(log_items.map(&:item_id)).to contain_exactly(post.id, comment_1.id, comment_2.id)
    end

    it 'supports custom column names' do
      item = ArchiveItem.create!(name: 'Custom')
      undo_log = item.soft_delete!

      expect(item.reload.soft_deleted?).to be true
      expect(item.archived_at).to be_present
      expect(undo_log.undo_log_items.first.item).to eq(item)
    end

    it 'cascades soft deletion for dependent: :delete_all associations' do
      delete_all_comment = post.delete_all_comments.create!(body: 'delete_all comment')
      post.soft_delete!

      expect(delete_all_comment.reload.soft_deleted?).to be true
    end

    it 'does not cascade soft deletion for dependent: :nullify associations' do
      like = post.likes.create!
      post.soft_delete!

      expect(like.reload.soft_deleted?).to be false
    end

    it 'cascades soft deletion recursively to nested associations' do
      reply = comment_1.replies.create!(post: post, body: 'Reply comment')
      post.soft_delete!

      expect(comment_1.reload.soft_deleted?).to be true
      expect(reply.reload.soft_deleted?).to be true
    end
  end

  describe '#restore!' do
    let!(:post) { Post.create!(title: 'Restorable Post') }
    let!(:comment) { post.comments.create!(body: 'Restorable Comment') }

    it 'restores all soft deleted records across the object tree in reverse order' do
      undo_log = post.soft_delete!

      expect(post.reload.soft_deleted?).to be true
      expect(comment.reload.soft_deleted?).to be true

      expect do
        undo_log.restore!
      end.to change(ActiveRecord::Undo::UndoLog, :count).by(-1)
                                                        .and change(ActiveRecord::Undo::UndoLogItem, :count).by(-2)

      expect(post.reload.soft_deleted?).to be false
      expect(comment.reload.soft_deleted?).to be false
    end

    it 'restores recursively nested associations' do
      reply = comment.replies.create!(post: post, body: 'Reply to restorable comment')
      undo_log = post.soft_delete!

      expect(post.reload.soft_deleted?).to be true
      expect(comment.reload.soft_deleted?).to be true
      expect(reply.reload.soft_deleted?).to be true

      undo_log.restore!

      expect(post.reload.soft_deleted?).to be false
      expect(comment.reload.soft_deleted?).to be false
      expect(reply.reload.soft_deleted?).to be false
    end

    it 'deletes the UndoLog and associated UndoLogItems from the database upon restore' do
      undo_log = post.soft_delete!
      log_id = undo_log.id
      item_ids = undo_log.undo_log_items.pluck(:id)

      expect(ActiveRecord::Undo::UndoLog.exists?(id: log_id)).to be true
      expect(ActiveRecord::Undo::UndoLogItem.where(id: item_ids).count).to eq(2)

      undo_log.restore!

      expect(ActiveRecord::Undo::UndoLog.exists?(id: log_id)).to be false
      expect(ActiveRecord::Undo::UndoLogItem.where(id: item_ids)).to be_empty
    end

    it 'restores models with custom soft-delete columns' do
      item = ArchiveItem.create!(name: 'Custom Archive')
      undo_log = item.soft_delete!

      expect(item.reload.soft_deleted?).to be true
      undo_log.restore!

      expect(item.reload.soft_deleted?).to be false
      expect(item.archived_at).to be_nil
    end

    it 'allows restoring directly from the model object using cascade' do
      post.soft_delete!

      expect(post.reload.soft_deleted?).to be true
      expect(comment.reload.soft_deleted?).to be true

      expect do
        post.restore!
      end.to change(ActiveRecord::Undo::UndoLog, :count).by(-1)
                                                        .and change(ActiveRecord::Undo::UndoLogItem, :count).by(-2)

      expect(post.reload.soft_deleted?).to be false
      expect(comment.reload.soft_deleted?).to be false
    end

    it 'falls back to simple restore if no UndoLogItem exists' do
      post.update_columns(deleted_at: Time.current)
      expect(post.reload.soft_deleted?).to be true

      post.restore!

      expect(post.reload.soft_deleted?).to be false
    end
  end

  describe 'error handling' do
    let!(:post) { Post.create!(title: 'Error Post') }

    context 'when the configured soft-delete column is missing' do
      before do
        allow(Post).to receive(:undoable_column).and_return(:missing_column)
      end

      it 'raises an ActiveRecord::Undo::Error on soft_delete!' do
        expect do
          post.soft_delete!
        end.to raise_error(ActiveRecord::Undo::Error, /configured soft-delete column 'missing_column' does not exist/)
      end

      it 'raises an ActiveRecord::Undo::Error on restore!' do
        post.update_columns(deleted_at: Time.current)
        expect do
          post.restore!
        end.to raise_error(ActiveRecord::Undo::Error, /configured soft-delete column 'missing_column' does not exist/)
      end
    end

    context 'when restoring with invalid data' do
      it 'raises an error if the model class cannot be loaded' do
        undo_log = post.soft_delete!
        log_item = undo_log.undo_log_items.first

        # Manually alter the item_type to a non-existent class
        log_item.update_columns(item_type: 'NonExistentClass')

        expect do
          undo_log.restore!
        end.to raise_error(ActiveRecord::Undo::Error, /model class 'NonExistentClass' could not be loaded/)
      end

      it 'raises an error if the model class is not an ActiveRecord model' do
        undo_log = post.soft_delete!
        log_item = undo_log.undo_log_items.first

        # Manually alter the item_type to a non-ActiveRecord class (e.g., 'String')
        log_item.update_columns(item_type: 'String')

        expect do
          undo_log.restore!
        end.to raise_error(ActiveRecord::Undo::Error, /is not an ActiveRecord model/)
      end

      it 'raises an error if the column does not exist on the class' do
        undo_log = post.soft_delete!
        log_item = undo_log.undo_log_items.first

        # Stub the model class column_names to not include 'deleted_at'
        allow(Post).to receive(:column_names).and_return([])

        expect do
          log_item.restore_item!
        end.to raise_error(ActiveRecord::Undo::Error, /column 'deleted_at' does not exist on 'Post' model/)
      end
    end
  end

  describe 'transaction rollback' do
    let!(:post) { Post.create!(title: 'Rollback Post') }
    let!(:comment) { post.comments.create!(body: 'Rollback Comment') }

    it 'rolls back the entire soft-deletion if an error is raised during cascade' do
      # Force an error to be raised when saving the comment (during cascade delete)
      allow_any_instance_of(Comment)
        .to receive(:soft_delete_cascade_internal!)
        .and_raise(RuntimeError, 'Database failure')

      expect do
        expect do
          post.soft_delete!
        end.to raise_error(RuntimeError, 'Database failure')
      end.not_to change(ActiveRecord::Undo::UndoLog, :count)

      expect(post.reload.soft_deleted?).to be false
      expect(comment.reload.soft_deleted?).to be false
    end

    it 'rolls back the entire restoration if an error is raised during restore' do
      undo_log = post.soft_delete!

      expect(post.reload.soft_deleted?).to be true
      expect(comment.reload.soft_deleted?).to be true

      # Force an error when restoring the comment
      allow_any_instance_of(ActiveRecord::Undo::UndoLogItem).to receive(:restore_item!).and_call_original
      allow_any_instance_of(ActiveRecord::Undo::UndoLogItem)
        .to receive(:restore_item!).with(no_args).and_wrap_original do |m, *args|
        # Raise error only if it is the comment being restored
        raise 'Restore failure' if m.receiver.item_type == 'Comment'

        m.call(*args)
      end

      expect do
        expect do
          undo_log.restore!
        end.to raise_error(RuntimeError, 'Restore failure')
      end.not_to change(ActiveRecord::Undo::UndoLog, :count)

      # Verify both remain soft-deleted
      expect(post.reload.soft_deleted?).to be true
      expect(comment.reload.soft_deleted?).to be true
    end
  end

  describe '#undoable?' do
    let!(:post) { Post.create!(title: 'Check Undoable') }

    it 'returns false for active (non-deleted) records' do
      expect(post.undoable?).to be false
    end

    it 'returns true when soft deleted via the gem and undo log exists' do
      post.soft_delete!
      expect(post.reload.undoable?).to be true
    end

    it 'returns false if soft-deleted manually without an undo log entry' do
      # Simulating a direct SQL update or legacy soft delete
      post.update_columns(deleted_at: Time.current)
      expect(post.reload.undoable?).to be false
    end

    it 'returns false after the undo log has been restored or destroyed' do
      undo_log = post.soft_delete!
      expect(post.reload.undoable?).to be true

      undo_log.restore!
      expect(post.reload.undoable?).to be false
    end
  end
end
