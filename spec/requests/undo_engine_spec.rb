# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'ActiveRecord::Undo::Engine Requests', type: :request do
  let!(:user) { User.create!(name: 'Alice') }
  let!(:account_1) { Account.create!(name: 'Account 1') }
  let!(:account_2) { Account.create!(name: 'Account 2') }

  before do
    ActiveRecord::Undo.whodunnit = nil
    ActiveRecord::Undo.current_tenant = nil
    ActiveRecord::Undo.configure do |config|
      config.retention_period = 30.days
      config.current_user_method = nil
      config.current_tenant_method = nil
      config.base_controller = '::ApplicationController'
      config.default_redirect_path = ->(main_app) { main_app.respond_to?(:root_path) ? main_app.root_path : '/' }
      config.error_handling = :auto
    end
  end

  after do
    ActiveRecord::Undo.whodunnit = nil
    ActiveRecord::Undo.current_tenant = nil
    ActiveRecord::Undo.configure do |config|
      config.retention_period = 30.days
      config.current_user_method = nil
      config.current_tenant_method = nil
      config.base_controller = '::ApplicationController'
      config.default_redirect_path = ->(main_app) { main_app.respond_to?(:root_path) ? main_app.root_path : '/' }
      config.error_handling = :auto
    end
  end

  describe 'POST /undo/logs/:id/restore (HTML)' do
    it 'restores the record and redirects to referer with flash notice' do
      post = Post.create!(title: 'HTML Restore Post')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:notice]).to eq('Record successfully restored.')
      expect(post.reload.soft_deleted?).to be false
      expect(ActiveRecord::Undo::UndoLog.find_by(id: undo_log.id)).to be_nil
    end

    it 'redirects to safe params[:redirect_to] with flash notice' do
      post = Post.create!(title: 'Redirect To Post')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: '/dashboard' }

      expect(response).to redirect_to('/dashboard')
      expect(flash[:notice]).to eq('Record successfully restored.')
      expect(post.reload.soft_deleted?).to be false
    end

    it 'falls back to default_redirect_path when referer and redirect_to are absent' do
      post = Post.create!(title: 'Fallback Redirect Post')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore"

      expect(response).to redirect_to('/')
      expect(flash[:notice]).to eq('Record successfully restored.')
      expect(post.reload.soft_deleted?).to be false
    end

    it 'ignores malicious open-redirect URLs in redirect_to' do
      post = Post.create!(title: 'Open Redirect Attack')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: 'https://evil.com/phish' }

      expect(response).to redirect_to('/')
      expect(response).not_to redirect_to('https://evil.com/phish')
    end

    it 'ignores protocol-relative open-redirect URLs' do
      post = Post.create!(title: 'Protocol Relative Attack')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: '//evil.com' }

      expect(response).to redirect_to('/')
      expect(response).not_to redirect_to('//evil.com')
    end

    it 'allows absolute URLs if matching host and port' do
      post = Post.create!(title: 'Same Host Absolute URL')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: 'http://www.example.com/dashboard' }

      expect(response).to redirect_to('http://www.example.com/dashboard')
    end

    it 'blocks javascript scheme URLs even if host matches' do
      post = Post.create!(title: 'XSS Scheme Attack')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: 'javascript://www.example.com/%0Aalert(1)' }

      expect(response).to redirect_to('/')
      expect(response).not_to redirect_to('javascript://www.example.com/%0Aalert(1)')
    end

    it 'blocks CRLF characters in redirect_to' do
      post = Post.create!(title: 'CRLF Attack')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: "/posts\r\nSet-Cookie: evil=1" }

      expect(response).to redirect_to('/')
    end

    it 'blocks port mismatch on same-host URLs' do
      post = Post.create!(title: 'Port Mismatch Attack')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", params: { redirect_to: 'http://www.example.com:9999/dashboard' }

      expect(response).to redirect_to('/')
    end

    it 'blocks data and vbscript schemes' do
      post_1 = Post.create!(title: 'Scheme Attack 1')
      log_1 = post_1.soft_delete!
      data_uri = 'data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg=='

      post "/undo/logs/#{log_1.id}/restore", params: { redirect_to: data_uri }
      expect(response).to redirect_to('/')

      post_2 = Post.create!(title: 'Scheme Attack 2')
      log_2 = post_2.soft_delete!

      post "/undo/logs/#{log_2.id}/restore", params: { redirect_to: 'vbscript:msgbox(1)' }
      expect(response).to redirect_to('/')
    end

    it 'safely falls back when redirect_to receives unexpected types (hash or array)' do
      post_1 = Post.create!(title: 'Parameter Tampering 1')
      log_1 = post_1.soft_delete!

      post "/undo/logs/#{log_1.id}/restore", params: { redirect_to: ['/dashboard'] }
      expect(response).to redirect_to('/')

      post_2 = Post.create!(title: 'Parameter Tampering 2')
      log_2 = post_2.soft_delete!

      post "/undo/logs/#{log_2.id}/restore", params: { redirect_to: { evil: 'true' } }
      expect(response).to redirect_to('/')
    end

    it 'responds with HTTP 303 See Other on HTML redirects' do
      post = Post.create!(title: 'Turbo 303 Redirect')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to have_http_status(:see_other)
    end
  end

  describe 'POST /undo/logs/:id/restore (JSON)' do
    it 'returns success status and restored_items_count payload' do
      post = Post.create!(title: 'JSON Post')
      post.comments.create!(body: 'Comment 1')
      post.comments.create!(body: 'Comment 2')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore", as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['restored_items_count']).to eq(3)
      expect(post.reload.soft_deleted?).to be false
    end
  end

  describe 'POST /undo/restore/:token (Signed Token Restoration)' do
    it 'restores the record using a signed token via HTML' do
      post = Post.create!(title: 'Signed Token Post')
      undo_log = post.soft_delete!
      token = undo_log.signed_token

      post "/undo/restore/#{token}", headers: { 'HTTP_REFERER' => '/dashboard' }

      expect(response).to redirect_to('/dashboard')
      expect(flash[:notice]).to eq('Record successfully restored.')
      expect(post.reload.soft_deleted?).to be false
    end

    it 'restores the record using a signed token via JSON' do
      post = Post.create!(title: 'Signed Token JSON Post')
      undo_log = post.soft_delete!
      token = undo_log.signed_token

      post "/undo/restore/#{token}", as: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json['success']).to be true
      expect(json['restored_items_count']).to eq(1)
      expect(post.reload.soft_deleted?).to be false
    end

    it 'rejects tampered signed tokens with 404 in JSON' do
      post = Post.create!(title: 'Tampered Token Post')
      undo_log = post.soft_delete!
      bad_token = "#{undo_log.signed_token}tampered"

      post "/undo/restore/#{bad_token}", as: :json

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/not found/i)
      expect(post.reload.soft_deleted?).to be true
    end

    it 'rejects signed tokens generated for a different purpose' do
      post = Post.create!(title: 'Wrong Purpose Post')
      undo_log = post.soft_delete!
      wrong_purpose_token = ActiveRecord::Undo::UndoLog.token_verifier.generate(undo_log.id, purpose: :other)

      post "/undo/restore/#{wrong_purpose_token}", as: :json

      expect(response).to have_http_status(:not_found)
      expect(post.reload.soft_deleted?).to be true
    end

    it 'rejects expired signed tokens' do
      post = Post.create!(title: 'Expired Signed Token Post')
      undo_log = post.soft_delete!
      expired_token = undo_log.signed_token(expires_in: 0.1.seconds)
      sleep 0.2

      post "/undo/restore/#{expired_token}", as: :json

      expect(response).to have_http_status(:not_found)
      expect(post.reload.soft_deleted?).to be true
    end

    it 'enforces tenant boundary security on signed token restoration' do
      tenant_post = Post.create!(title: 'Tenant Signed Post', tenant: account_1)
      undo_log = tenant_post.soft_delete!(tenant: account_1)
      valid_token = undo_log.signed_token

      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/restore/#{valid_token}", as: :json

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Tenant mismatch/i)
      expect(tenant_post.reload.soft_deleted?).to be true
    end

    it 'redirects with alert when restoring via signed token with mismatched tenant in HTML' do
      tenant_post = Post.create!(title: 'Tenant Signed Post HTML', tenant: account_1)
      undo_log = tenant_post.soft_delete!(tenant: account_1)
      valid_token = undo_log.signed_token

      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/restore/#{valid_token}", headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:alert]).to match(/Tenant mismatch/i)
      expect(tenant_post.reload.soft_deleted?).to be true
    end
  end

  describe 'Missing and Already Restored Logs' do
    it 'returns 404 Not Found for non-existent ID in JSON' do
      post '/undo/logs/9999999/restore', as: :json

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/not found or already restored/i)
    end

    it 'returns 404 Not Found for non-numeric ID without raising database errors' do
      post '/undo/logs/non-numeric-identifier/restore', as: :json

      expect(response).to have_http_status(:not_found)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/not found or already restored/i)
    end

    it 'safely returns nil when find_by_signed_token receives non-string input' do
      expect(ActiveRecord::Undo::UndoLog.find_by_signed_token(12_345)).to be_nil
      expect(ActiveRecord::Undo::UndoLog.find_by_signed_token(nil)).to be_nil
      expect(ActiveRecord::Undo::UndoLog.find_by_signed_token(['array'])).to be_nil
    end

    it 'returns 404 Not Found for non-existent ID in HTML when no referer is provided' do
      post '/undo/logs/9999999/restore'

      expect(response).to have_http_status(:not_found)
      expect(response.body).to match(/not found or already restored/i)
    end

    it 'redirects with flash alert for non-existent ID in HTML when referer is present' do
      post '/undo/logs/9999999/restore', headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:alert]).to match(/not found or already restored/i)
    end

    it 'returns 404 when log has already been restored' do
      post = Post.create!(title: 'Double Restore Post')
      undo_log = post.soft_delete!
      undo_log_id = undo_log.id

      # First restore succeeds
      post "/undo/logs/#{undo_log_id}/restore", as: :json
      expect(response).to have_http_status(:ok)

      # Second restore yields 404
      post "/undo/logs/#{undo_log_id}/restore", as: :json
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'Expired Logs' do
    it 'returns 422 Unprocessable Entity for expired logs in JSON' do
      post = Post.create!(title: 'Expired Post')
      undo_log = post.soft_delete!
      undo_log.update_column(:created_at, 35.days.ago)

      post "/undo/logs/#{undo_log.id}/restore", as: :json

      expect(response).to have_http_status(422)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/expired/i)
      expect(post.reload.soft_deleted?).to be true
    end

    it 'returns 422 Unprocessable Entity for expired logs in HTML without referer' do
      post = Post.create!(title: 'Expired HTML Post')
      undo_log = post.soft_delete!
      undo_log.update_column(:created_at, 35.days.ago)

      post "/undo/logs/#{undo_log.id}/restore"

      expect(response).to have_http_status(422)
      expect(response.body).to match(/expired/i)
    end

    it 'redirects with alert for expired logs in HTML when referer is present' do
      post = Post.create!(title: 'Expired HTML Referer Post')
      undo_log = post.soft_delete!
      undo_log.update_column(:created_at, 35.days.ago)

      post "/undo/logs/#{undo_log.id}/restore", headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:alert]).to match(/expired/i)
    end
  end

  describe 'Tenant Isolation and Security Verification' do
    let!(:tenant_post) do
      p = Post.create!(title: 'Tenant Security Post', tenant: account_1)
      p.soft_delete!(tenant: account_1)
      p
    end
    let!(:undo_log) { tenant_post.send(:find_latest_undo_log_item).undo_log }

    it 'succeeds when current tenant matches log tenant' do
      ActiveRecord::Undo.current_tenant = account_1

      post "/undo/logs/#{undo_log.id}/restore", as: :json

      expect(response).to have_http_status(:ok)
      expect(tenant_post.reload.soft_deleted?).to be false
    end

    it 'returns 403 Forbidden in JSON when tenant mismatches' do
      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/logs/#{undo_log.id}/restore", as: :json

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Tenant mismatch/i)
      expect(tenant_post.reload.soft_deleted?).to be true
    end

    it 'returns 403 Forbidden in HTML without referer when tenant mismatches' do
      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/logs/#{undo_log.id}/restore"

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to match(/Tenant mismatch/i)
      expect(tenant_post.reload.soft_deleted?).to be true
    end

    it 'redirects with alert in HTML with referer when tenant mismatches' do
      ActiveRecord::Undo.current_tenant = account_2

      post "/undo/logs/#{undo_log.id}/restore", headers: { 'HTTP_REFERER' => '/posts' }

      expect(response).to redirect_to('/posts')
      expect(flash[:alert]).to match(/Tenant mismatch/i)
      expect(tenant_post.reload.soft_deleted?).to be true
    end

    it 'handles unauthenticated action when context method returns nil' do
      ActiveRecord::Undo.configure do |config|
        config.current_user_method = -> {}
        config.current_tenant_method = -> {}
      end

      post "/undo/logs/#{undo_log.id}/restore", as: :json

      expect(response).to have_http_status(:forbidden)
      json = JSON.parse(response.body)
      expect(json['error']).to match(/Configured current_user_method and current_tenant_method both returned nil/i)
    end
  end

  describe 'User Attribution (whodunnit)' do
    it 'sets whodunnit attribution during restoration' do
      post = Post.create!(title: 'Attribution Post')
      undo_log = post.soft_delete!

      ActiveRecord::Undo.configure do |config|
        config.current_user_method = -> { user }
      end

      observed_actor = nil
      allow_any_instance_of(ActiveRecord::Undo::UndoLog).to receive(:restore!).and_wrap_original do |m, *args, **kwargs|
        observed_actor = kwargs[:whodunnit] || ActiveRecord::Undo.whodunnit
        m.call(*args, **kwargs)
      end

      post "/undo/logs/#{undo_log.id}/restore", as: :json

      expect(response).to have_http_status(:ok)
      expect(observed_actor).to eq(user)
    end
  end

  describe 'Turbo Stream format' do
    it 'responds with turbo stream markup on success' do
      post = Post.create!(title: 'Turbo Post')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore",
           headers: { 'Accept' => 'text/vnd.turbo-stream.html, text/html' }

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('<turbo-stream')
      expect(response.body).to include('Record successfully restored.')
      expect(post.reload.soft_deleted?).to be false
    end

    it 'responds with turbo stream markup and error status on failure' do
      post = Post.create!(title: 'Turbo Error Post')
      undo_log = post.soft_delete!

      ActiveRecord::Undo.configure do |config|
        config.current_user_method = -> {}
        config.current_tenant_method = -> {}
      end

      post "/undo/logs/#{undo_log.id}/restore",
           headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

      expect(response).to have_http_status(:forbidden)
      expect(response.media_type).to eq('text/vnd.turbo-stream.html')
      expect(response.body).to include('<turbo-stream')
      expect(response.body).to include('undo-alert')
    end
  end

  describe 'Custom Configuration' do
    it 'uses custom default_redirect_path lambda' do
      ActiveRecord::Undo.configure do |config|
        config.default_redirect_path = ->(_main_app) { '/custom_fallback' }
      end
      post = Post.create!(title: 'Custom Redirect Post')
      undo_log = post.soft_delete!

      post "/undo/logs/#{undo_log.id}/restore"

      expect(response).to redirect_to('/custom_fallback')
    end
  end
end
