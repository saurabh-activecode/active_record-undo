# spec/internal/app/models/models.rb
# frozen_string_literal: true

class Post < ActiveRecord::Base
  acts_as_undoable

  has_many :comments, dependent: :destroy
  has_many :delete_all_comments, class_name: 'Comment', dependent: :delete_all
  has_many :likes, dependent: :nullify
end

class Comment < ActiveRecord::Base
  acts_as_undoable

  belongs_to :post
  belongs_to :comment, optional: true, class_name: 'Comment'
  has_many :replies, class_name: 'Comment', foreign_key: 'comment_id', dependent: :destroy
end

class Like < ActiveRecord::Base
  acts_as_undoable
  belongs_to :post
end

class ArchiveItem < ActiveRecord::Base
  # Test custom soft-delete column support
  acts_as_undoable column: :archived_at
end
