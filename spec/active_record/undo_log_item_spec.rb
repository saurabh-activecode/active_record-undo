# spec/active_record/undo_log_item_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Undo::UndoLogItem do
  describe '#restore_item!' do
    let(:post) { Post.create!(title: 'Post', deleted_at: Time.current) }
    let(:undo_log) { ActiveRecord::Undo::UndoLog.create! }

    it 'resets the soft-delete column to nil' do
      log_item = undo_log.undo_log_items.create!(item: post)
      expect(post.soft_deleted?).to be true

      log_item.restore_item!

      expect(post.reload.soft_deleted?).to be false
      expect(post.deleted_at).to be_nil
    end

    it 'raises an ActiveRecord::Undo::Error if the model class cannot be loaded' do
      log_item = undo_log.undo_log_items.create!(item: post)
      log_item.update_columns(item_type: 'NonExistentClass')

      expect do
        log_item.restore_item!
      end.to raise_error(ActiveRecord::Undo::Error, /model class 'NonExistentClass' could not be loaded/)
    end

    it 'raises an ActiveRecord::Undo::Error if the model class is not an ActiveRecord model' do
      log_item = undo_log.undo_log_items.create!(item: post)
      log_item.update_columns(item_type: 'String')

      expect do
        log_item.restore_item!
      end.to raise_error(ActiveRecord::Undo::Error, /is not an ActiveRecord model/)
    end

    it 'raises an ActiveRecord::Undo::Error if the column does not exist on the class' do
      log_item = undo_log.undo_log_items.create!(item: post)
      allow(Post).to receive(:column_names).and_return([])

      expect do
        log_item.restore_item!
      end.to raise_error(ActiveRecord::Undo::Error, /column 'deleted_at' does not exist on 'Post' model/)
    end
  end
end
