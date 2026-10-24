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

    it 'responds with turbo stream markup and 202 Accepted' do
      post "/undo/logs/#{undo_log.id}/restore",
           params: { async: true },
           headers: { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('<turbo-stream action="append" target="notifications">')
      expect(response.body).to include('Restoration has been scheduled and is processing.')
      expect(undo_log.reload.status).to eq('pending')
    end

    it 'returns 403 Forbidden when tenant mismatches in JSON' do
      account_1 = Account.create!(name: 'Tenant 1')
      account_2 = Account.create!(name: 'Tenant 2')
      tenant_post = Post.create!(title: 'Tenant Mismatch Post', tenant: account_1)
      tenant_log = tenant_post.soft_delete!(tenant: account_1)

      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/logs/#{tenant_log.id}/restore",
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Tenant mismatch/i)
      expect(tenant_log.reload.status).to eq('completed')
    end

    it 'redirects with alert when tenant mismatches in HTML with referer' do
      account_1 = Account.create!(name: 'Tenant 1')
      account_2 = Account.create!(name: 'Tenant 2')
      tenant_post = Post.create!(title: 'Tenant HTML Post', tenant: account_1)
      tenant_log = tenant_post.soft_delete!(tenant: account_1)

      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/logs/#{tenant_log.id}/restore",
           params: { async: true },
           headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:alert]).to match(/Tenant mismatch/i)
    end

    it 'returns 422 Unprocessable Entity when log is expired' do
      undo_log.update_columns(created_at: 35.days.ago)

      post "/undo/logs/#{undo_log.id}/restore",
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/expired/i)
    end

    it 'returns 422 when log is currently processing' do
      undo_log.update_columns(status: 1) # processing

      post "/undo/logs/#{undo_log.id}/restore",
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/currently processing/i)
    end

    it 'returns 422 when log is already pending restore' do
      undo_log.update_columns(action: 1, status: 0) # pending restore

      post "/undo/logs/#{undo_log.id}/restore",
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/already scheduled for restore/i)
    end

    it 'returns 404 when log does not exist' do
      post '/undo/logs/999999/restore',
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/not found/i)
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

    it 'responds with turbo stream markup on async token restore' do
      post "/undo/restore/#{token}",
           params: { async: true },
           headers: { 'ACCEPT' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:accepted)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('Restoration has been scheduled and is processing.')
    end

    it 'rejects invalid token with 404 Not Found' do
      post '/undo/restore/invalid-token-12345',
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:not_found)
    end

    it 'enforces tenant boundary on async token restore' do
      account_1 = Account.create!(name: 'Account 1')
      account_2 = Account.create!(name: 'Account 2')
      tenant_post = Post.create!(title: 'Tenant Post', tenant: account_1)
      t_log = tenant_post.soft_delete!(tenant: account_1)
      t_token = t_log.signed_token

      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/restore/#{t_token}",
           params: { async: true },
           headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Tenant mismatch/i)
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
      expect(json['completed']).to be false
      expect(json['failed']).to be false
    end

    it 'renders plain text status in HTML format' do
      get "/undo/logs/#{undo_log.id}/status", headers: { 'ACCEPT' => 'text/html' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('processing')
    end

    it 'returns 404 when log does not exist' do
      get '/undo/logs/999999/status', headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/not found/i)
    end

    it 'returns 422 when log is expired' do
      undo_log.update_columns(created_at: 35.days.ago)

      get "/undo/logs/#{undo_log.id}/status", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/expired/i)
    end

    it 'returns 403 Forbidden when tenant mismatches on status check' do
      account_1 = Account.create!(name: 'Account 1')
      account_2 = Account.create!(name: 'Account 2')
      undo_log.update!(tenant: account_1)

      ActiveRecord::Undo.current_tenant = account_2

      get "/undo/logs/#{undo_log.id}/status", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Tenant mismatch/i)
    end

    it 'exposes error_message and failed status flags when an operation fails' do
      undo_log.update!(status: :failed, error_message: 'Out of memory on worker')

      get "/undo/logs/#{undo_log.id}/status", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['status']).to eq('failed')
      expect(json['error_message']).to eq('Out of memory on worker')
      expect(json['completed']).to be false
      expect(json['failed']).to be true
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
      expect(json['completed']).to be false
      expect(json['failed']).to be false
    end

    it 'renders plain text status in HTML format' do
      get "/undo/status/#{token}", headers: { 'ACCEPT' => 'text/html' }

      expect(response).to have_http_status(:ok)
      expect(response.body).to eq('pending')
    end

    it 'returns 404 when signed token is tampered' do
      get "/undo/status/#{token}corrupt", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:not_found)
    end

    it 'enforces tenant boundary security on signed status lookup' do
      account_1 = Account.create!(name: 'Account 1')
      account_2 = Account.create!(name: 'Account 2')
      undo_log.update!(tenant: account_1)

      ActiveRecord::Undo.current_tenant = account_2

      get "/undo/status/#{token}", headers: { 'ACCEPT' => 'application/json' }

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Tenant mismatch/i)
    end
  end
end
