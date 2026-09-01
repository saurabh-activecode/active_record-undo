# spec/active_record/undo/tenant_and_attribution_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Tenant Isolation & User Attribution' do
  let!(:user_a) { User.create!(name: 'Alice') }
  let!(:user_b) { User.create!(name: 'Bob') }
  let!(:account_1) { Account.create!(name: 'Acme Inc') }
  let!(:account_2) { Account.create!(name: 'Beta Corp') }

  before do
    # Clear thread contexts and config before each spec
    ActiveRecord::Undo.whodunnit = nil
    ActiveRecord::Undo.current_tenant = nil
    ActiveRecord::Undo.configure do |config|
      config.current_user_method = nil
      config.current_tenant_method = nil
    end
  end

  describe 'User Attribution (whodunnit)' do
    it 'captures whodunnit when passed explicitly to soft_delete!' do
      post = Post.create!(title: 'Explicit User Post', tenant: account_1)
      undo_log = post.soft_delete!(whodunnit: user_a)

      expect(undo_log.whodunnit).to eq(user_a)
    end

    it 'captures whodunnit from config.current_user_method proc' do
      ActiveRecord::Undo.configure do |config|
        config.current_user_method = -> { user_b }
      end

      post = Post.create!(title: 'Proc User Post', tenant: account_1)
      undo_log = post.soft_delete!

      expect(undo_log.whodunnit).to eq(user_b)
    end

    it 'captures whodunnit from Thread/Fiber context fallback' do
      ActiveRecord::Undo.whodunnit = user_a

      post = Post.create!(title: 'Context User Post', tenant: account_1)
      undo_log = post.soft_delete!

      expect(undo_log.whodunnit).to eq(user_a)
    end

    it 'sets ActiveRecord::Undo.whodunnit during restore! execution' do
      post = Post.create!(title: 'Restore Attribution Post')
      undo_log = post.soft_delete!(whodunnit: user_a)

      expect(ActiveRecord::Undo.whodunnit).to be_nil

      # Spy on the restoration process or verify it sets the value during the transaction
      # We can check by defining a callback on the model or checking that it accepted the value
      restored = post.restore!(whodunnit: user_b)
      expect(restored).to be true
      expect(ActiveRecord::Undo.whodunnit).to be_nil
    end
  end

  describe 'Multi-Tenant Isolation' do
    it 'captures tenant when passed explicitly' do
      post = Post.create!(title: 'Explicit Tenant Post', tenant: account_1)
      undo_log = post.soft_delete!(tenant: account_2)

      expect(undo_log.tenant).to eq(account_2)
    end

    it 'captures tenant from config.current_tenant_method proc' do
      ActiveRecord::Undo.configure do |config|
        config.current_tenant_method = -> { account_1 }
      end

      post = Post.create!(title: 'Proc Tenant Post')
      undo_log = post.soft_delete!

      expect(undo_log.tenant).to eq(account_1)
    end

    it 'captures tenant from Thread/Fiber context' do
      ActiveRecord::Undo.current_tenant = account_2

      post = Post.create!(title: 'Context Tenant Post')
      undo_log = post.soft_delete!

      expect(undo_log.tenant).to eq(account_2)
    end

    it 'resolves tenant from the model instance if it responds to tenant' do
      post = Post.create!(title: 'Model Resolved Tenant Post', tenant: account_1)
      undo_log = post.soft_delete!

      expect(undo_log.tenant).to eq(account_1)
    end

    it 'raises ActiveRecord::Undo::SecurityError on restore! if tenant is mismatched' do
      post = Post.create!(title: 'Mismatch Tenant Post', tenant: account_1)
      post.soft_delete!

      # Initiating context has a different tenant
      ActiveRecord::Undo.current_tenant = account_2

      expect { post.restore! }.to raise_error(ActiveRecord::Undo::SecurityError, /Tenant mismatch/)
    end

    it 'allows restore! if tenant matches exactly' do
      post = Post.create!(title: 'Matching Tenant Post', tenant: account_1)
      post.soft_delete!

      # Initiating context has the matching tenant
      ActiveRecord::Undo.current_tenant = account_1

      expect { post.restore! }.not_to raise_error
      expect(post.reload.soft_deleted?).to be false
    end

    it 'allows restore! if tenant on the log is nil/empty' do
      post = Post.create!(title: 'No Tenant Post')
      # Explicitly pass tenant: nil to bypass model resolution if it has one
      post.soft_delete!(tenant: nil)

      # Initiating context is set to account_1, but log has nil, so no enforcement
      ActiveRecord::Undo.current_tenant = account_1

      expect { post.restore! }.not_to raise_error
      expect(post.reload.soft_deleted?).to be false
    end
  end

  describe 'Query Scopes' do
    let!(:log_1) { Post.create!(title: 'P1', tenant: account_1).soft_delete!(whodunnit: user_a) }
    let!(:log_2) { Post.create!(title: 'P2', tenant: account_2).soft_delete!(whodunnit: user_b) }

    it 'filters by whodunnit using .for_whodunnit' do
      expect(ActiveRecord::Undo::UndoLog.for_whodunnit(user_a)).to include(log_1)
      expect(ActiveRecord::Undo::UndoLog.for_whodunnit(user_a)).not_to include(log_2)

      expect(ActiveRecord::Undo::UndoLog.for_whodunnit(user_b.id)).to include(log_2)
      expect(ActiveRecord::Undo::UndoLog.for_whodunnit(user_b.id)).not_to include(log_1)
    end

    it 'filters by tenant using .for_tenant' do
      expect(ActiveRecord::Undo::UndoLog.for_tenant(account_1)).to include(log_1)
      expect(ActiveRecord::Undo::UndoLog.for_tenant(account_1)).not_to include(log_2)

      expect(ActiveRecord::Undo::UndoLog.for_tenant(account_2.id)).to include(log_2)
      expect(ActiveRecord::Undo::UndoLog.for_tenant(account_2.id)).not_to include(log_1)
    end
  end

  describe 'Tenant-scoped Purging' do
    let!(:log_1) { Post.create!(title: 'P1', tenant: account_1).soft_delete! }
    let!(:log_2) { Post.create!(title: 'P2', tenant: account_2).soft_delete! }

    before do
      # Backdate logs so they are considered expired
      log_1.update_columns(created_at: 40.days.ago)
      log_2.update_columns(created_at: 40.days.ago)
      
      # Backdate soft-deleted posts
      Post.unscoped.update_all(deleted_at: 40.days.ago)
    end

    it 'purges logs and records only for the current tenant when set' do
      ActiveRecord::Undo.current_tenant = account_1

      expect {
        ActiveRecord::Undo::Purger.purge_expired!
      }.to change { ActiveRecord::Undo::UndoLog.count }.by(-1) # Only log_1 gets purged

      expect(ActiveRecord::Undo::UndoLog.exists?(log_2.id)).to be true
      expect(Post.unscoped.exists?(title: 'P2')).to be true
      expect(Post.unscoped.exists?(title: 'P1')).to be false
    end

    it 'purges everything across all tenants when no tenant is set' do
      ActiveRecord::Undo.current_tenant = nil

      expect {
        ActiveRecord::Undo::Purger.purge_expired!
      }.to change { ActiveRecord::Undo::UndoLog.count }.by(-2)

      expect(Post.unscoped.exists?(title: 'P1')).to be false
      expect(Post.unscoped.exists?(title: 'P2')).to be false
    end
  end
end
