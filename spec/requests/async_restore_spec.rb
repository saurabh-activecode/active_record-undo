# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Async Restore and Status Requests', type: :request do
  let!(:user) { User.create!(name: 'Alice') }
  let!(:post_record) { Post.create!(title: 'Async Request Post') }

  before do
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
    ActiveRecord::Undo.whodunnit = nil
    ActiveRecord::Undo.current_tenant = nil
  end

  describe 'POST /undo/logs/:id/restore with async: true' do
    let!(:undo_log) do
      post_record.soft_delete!
    end

    it 'schedules restore and redirects with notice in HTML format' do
      post "/undo/logs/#{undo_log.id}/restore", params: { async: true }, headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:notice]).to eq('Restoration has been scheduled and is processing.')
      expect(undo_log.reload.status).to eq('pending')
      expect(undo_log.action).to eq('restore')

      expect(ActiveRecord::Undo::RestoreJob).to have_been_enqueued.with(undo_log.id, whodunnit: nil)
    end

    it 'schedules restore and renders 202 Accepted in JSON format' do
      post "/undo/logs/#{undo_log.id}/restore",
           params: { async: 'true' },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['status']).to eq('pending')
      expect(json['log_id']).to eq(undo_log.id)

      expect(undo_log.reload.status).to eq('pending')
      expect(ActiveRecord::Undo::RestoreJob).to have_been_enqueued.with(undo_log.id, whodunnit: nil)
    end

    it 'supports X-Undo-Async header for asynchronous restoration' do
      post "/undo/logs/#{undo_log.id}/restore",
           headers: { 'X-Undo-Async' => 'true', 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('pending')
      expect(ActiveRecord::Undo::RestoreJob).to have_been_enqueued.with(undo_log.id, whodunnit: nil)
    end
  end

  describe 'POST /undo/restore/:token with async: true' do
    let!(:undo_log) { post_record.soft_delete! }
    let!(:token) { undo_log.signed_token }

    it 'schedules restore via signed token and returns 202 Accepted in JSON' do
      post "/undo/restore/#{token}",
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:accepted)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['status']).to eq('pending')
      expect(json['log_id']).to eq(undo_log.id)

      expect(ActiveRecord::Undo::RestoreJob).to have_been_enqueued.with(undo_log.id, whodunnit: nil)
    end
  end

  describe 'GET /undo/logs/:id/status' do
    let!(:undo_log) do
      l = ActiveRecord::Undo::UndoLog.create!(action: :soft_delete, status: :processing)
      l.undo_log_items.create!(item: post_record)
      l
    end

    it 'returns JSON payload with current operation statuses' do
      get "/undo/logs/#{undo_log.id}/status", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['id']).to eq(undo_log.id)
      expect(json['action']).to eq('soft_delete')
      expect(json['status']).to eq('processing')
      expect(json['soft_delete_status']).to eq('processing')
      expect(json['restore_status']).to be_nil
      expect(json['error_message']).to be_nil
    end
  end

  describe 'GET /undo/status/:token' do
    let!(:undo_log) do
      l = ActiveRecord::Undo::UndoLog.create!(action: :restore, status: :pending)
      l.undo_log_items.create!(item: post_record)
      l
    end
    let!(:token) { undo_log.signed_token }

    it 'returns JSON payload using signed token' do
      get "/undo/status/#{token}", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['id']).to eq(undo_log.id)
      expect(json['action']).to eq('restore')
      expect(json['status']).to eq('pending')
      expect(json['restore_status']).to eq('pending')
      expect(json['soft_delete_status']).to eq('completed')
    end
  end
end
