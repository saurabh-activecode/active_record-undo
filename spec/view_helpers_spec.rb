# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ActiveRecord::Undo::ViewHelpers, type: :helper do
  # Include ActionView helpers and ActiveRecord::Undo::ViewHelpers in a test view context
  let(:view_context) do
    lookup_context = ActionView::LookupContext.new([])
    ActionView::Base.new(lookup_context, {}, nil).tap do |view|
      view.extend ActionView::Helpers::UrlHelper
      view.extend ActionView::Helpers::FormTagHelper
      view.extend ActiveRecord::Undo::ViewHelpers
      # Define routes proxy mock or include engine routes
      view.define_singleton_method(:active_record_undo) do
        ActiveRecord::Undo::Engine.routes.url_helpers
      end
    end
  end

  let!(:post_item) do
    3.times { |i| Post.create!(title: "Pre #{i}") }
    p = Post.create!(title: 'Helper Post')
    p.soft_delete!
    p
  end
  let!(:undo_log) { post_item.undo_log }

  describe '#undo_button_to' do
    it 'generates a button_to form targeting the restore route' do
      html = view_context.undo_button_to(undo_log)

      expect(html).to include("action=\"/undo/logs/#{undo_log.id}/restore\"")
      expect(html).to include('value="Undo"')
    end

    it 'accepts custom button text as positional argument' do
      html = view_context.undo_button_to(undo_log, 'Revert Changes')

      expect(html).to include('value="Revert Changes"')
    end

    it 'accepts custom button text as keyword argument' do
      html = view_context.undo_button_to(undo_log, text: 'Restore Record', class: 'btn-primary')

      expect(html).to include('value="Restore Record"')
      expect(html).to include('class="btn-primary"')
    end

    it 'generates a signed restore path when signed: true' do
      html = view_context.undo_button_to(undo_log, signed: true)

      expect(html).to include('/undo/restore/')
      expect(html).not_to include("/undo/logs/#{undo_log.id}/restore")
    end

    it 'works when passed a model object whose id differs from undo_log id' do
      expect(post_item.id).not_to eq(undo_log.id)
      html = view_context.undo_button_to(post_item)

      expect(html).to include("action=\"/undo/logs/#{undo_log.id}/restore\"")
      expect(html).not_to include("action=\"/undo/logs/#{post_item.id}/restore\"")
    end

    it 'generates signed restore button when passed a model object' do
      html = view_context.undo_button_to(post_item, signed: true)
      token = html[%r{/undo/restore/([^"/?]+)}, 1]

      expect(token).to be_present
      expect(ActiveRecord::Undo::UndoLog.find_by_signed_token(token)).to eq(undo_log)
    end

    it 'raises ArgumentError when passed an active, non-soft-deleted model' do
      active_post = Post.create!(title: 'Active Post')

      expect do
        view_context.undo_button_to(active_post)
      end.to raise_error(ArgumentError, /Cannot resolve undo log/)
    end

    it 'raises ArgumentError when passed an active model with signed: true' do
      active_post = Post.create!(title: 'Active Post')

      expect do
        view_context.undo_button_to(active_post, signed: true)
      end.to raise_error(ArgumentError, /Cannot generate signed token/)
    end
  end

  describe '#undo_link_to' do
    it 'generates an anchor link with turbo-method post' do
      html = view_context.undo_link_to(undo_log)

      expect(html).to include("href=\"/undo/logs/#{undo_log.id}/restore\"")
      expect(html).to include('data-turbo-method="post"')
      expect(html).to include('>Undo</a>')
    end

    it 'accepts custom text and html classes' do
      html = view_context.undo_link_to(undo_log, 'Rollback', class: 'text-danger')

      expect(html).to include('class="text-danger"')
      expect(html).to include('>Rollback</a>')
    end

    it 'generates a signed restore link when signed: true' do
      html = view_context.undo_link_to(undo_log, signed: true)

      expect(html).to include('/undo/restore/')
    end

    it 'works when passed a model object' do
      html = view_context.undo_link_to(post_item)

      expect(html).to include("href=\"/undo/logs/#{undo_log.id}/restore\"")
      expect(html).not_to include("href=\"/undo/logs/#{post_item.id}/restore\"")
    end

    it 'generates a signed restore link when passed a model object' do
      html = view_context.undo_link_to(post_item, signed: true)
      token = html[%r{/undo/restore/([^"/?]+)}, 1]

      expect(token).to be_present
      expect(ActiveRecord::Undo::UndoLog.find_by_signed_token(token)).to eq(undo_log)
    end

    it 'raises ArgumentError when passed an active, non-soft-deleted model' do
      active_post = Post.create!(title: 'Active Post')

      expect do
        view_context.undo_link_to(active_post)
      end.to raise_error(ArgumentError, /Cannot resolve undo log/)
    end
  end

  describe 'Model edge cases' do
    it 'returns nil for undo_log on unpersisted records' do
      unpersisted = Post.new(title: 'Unpersisted', deleted_at: Time.current)
      expect(unpersisted.undo_log).to be_nil
    end

    it 'returns false for undoable? on unpersisted records' do
      unpersisted = Post.new(title: 'Unpersisted', deleted_at: Time.current)
      expect(unpersisted.undoable?).to be false
    end
  end
end
