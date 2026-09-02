# spec/active_record/undo/tenant_and_attribution_spec.rb
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Multi-Tenant Isolation & User Attribution' do
  let!(:user_a) { User.create!(name: 'Alice') }
  let!(:user_b) { User.create!(name: 'Bob') }
  let!(:account_1) { Account.create!(name: 'Acme Inc') }
  let!(:account_2) { Account.create!(name: 'Beta Corp') }

  before do
    ActiveRecord::Undo.whodunnit = nil
    ActiveRecord::Undo.current_tenant = nil
    ActiveRecord::Undo.configure do |config|
      config.current_user_method = nil
      config.current_tenant_method = nil
    end
  end

  after do
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
      post.soft_delete!(whodunnit: user_a)

      observed_actor = nil
      allow_any_instance_of(ActiveRecord::Undo::UndoLog).to receive(:restore!).and_wrap_original do |m|
        observed_actor = ActiveRecord::Undo.whodunnit
        m.call
      end

      restored = post.restore!(whodunnit: user_b)
      expect(restored).to be true
      expect(observed_actor).to eq(user_b)
      expect(ActiveRecord::Undo.whodunnit).to be_nil
    end
  end

  describe 'Multi-Tenant Isolation' do
    describe 'tenant capture during soft_delete!' do
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
    end

    describe 'tenant matching verification during restore!' do
      let!(:tenant_post) do
        post = Post.create!(title: 'Tenant Post', tenant: account_1)
        post.soft_delete!
        post
      end

      it 'allows restore! if tenant matches via thread context' do
        ActiveRecord::Undo.current_tenant = account_1

        expect { tenant_post.restore! }.not_to raise_error
        expect(tenant_post.reload.soft_deleted?).to be false
      end

      it 'allows restore! if tenant matches via config.current_tenant_method proc' do
        ActiveRecord::Undo.configure do |config|
          config.current_tenant_method = -> { account_1 }
        end

        expect { tenant_post.restore! }.not_to raise_error
        expect(tenant_post.reload.soft_deleted?).to be false
      end

      it 'allows restore! if tenant matches via scalar ID in thread context' do
        ActiveRecord::Undo.current_tenant = account_1.id

        expect { tenant_post.restore! }.not_to raise_error
        expect(tenant_post.reload.soft_deleted?).to be false
      end

      it 'allows restore! if tenant on the log is nil' do
        post = Post.create!(title: 'No Tenant Post')
        post.soft_delete!(tenant: nil)

        ActiveRecord::Undo.current_tenant = account_1

        expect { post.restore! }.not_to raise_error
        expect(post.reload.soft_deleted?).to be false
      end

      it 'raises ActiveRecord::Undo::SecurityError if tenant is mismatched via thread context' do
        ActiveRecord::Undo.current_tenant = account_2

        expect { tenant_post.restore! }.to raise_error(ActiveRecord::Undo::SecurityError, /Tenant mismatch/)
      end

      it 'raises ActiveRecord::Undo::SecurityError if tenant is mismatched via proc' do
        ActiveRecord::Undo.configure do |config|
          config.current_tenant_method = -> { account_2 }
        end

        expect { tenant_post.restore! }.to raise_error(ActiveRecord::Undo::SecurityError, /Tenant mismatch/)
      end

      it 'raises ActiveRecord::Undo::SecurityError if record had a tenant but restore context has none' do
        ActiveRecord::Undo.current_tenant = nil

        expect { tenant_post.restore! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Tenant mismatch: log belongs to tenant Account##{account_1.id}, but current context tenant is nil\./
        )
      end
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
      log_1.update_columns(created_at: 40.days.ago)
      log_2.update_columns(created_at: 40.days.ago)
      Post.unscoped.update_all(deleted_at: 40.days.ago)
    end

    it 'purges logs and records only for the current tenant when set' do
      ActiveRecord::Undo.current_tenant = account_1

      expect do
        ActiveRecord::Undo::Purger.purge_expired!
      end.to change { ActiveRecord::Undo::UndoLog.count }.by(-1)
      expect(ActiveRecord::Undo::UndoLog.exists?(log_2.id)).to be true
      expect(Post.unscoped.exists?(title: 'P2')).to be true
      expect(Post.unscoped.exists?(title: 'P1')).to be false
    end

    it 'purges everything across all tenants when no tenant is set' do
      ActiveRecord::Undo.current_tenant = nil

      expect do
        ActiveRecord::Undo::Purger.purge_expired!
      end.to change { ActiveRecord::Undo::UndoLog.count }.by(-2)

      expect(Post.unscoped.exists?(title: 'P1')).to be false
      expect(Post.unscoped.exists?(title: 'P2')).to be false
    end
  end

  describe 'Enforcement of configured user and tenant methods' do
    let!(:deleted_post) do
      post = Post.create!(title: 'Pre-deleted Post', tenant: account_1)
      post.soft_delete!(tenant: account_1)
      post
    end

    describe 'when current_user and current_tenant both return null' do
      before do
        ActiveRecord::Undo.configure do |config|
          config.current_user_method = -> {}
          config.current_tenant_method = -> {}
        end
      end

      it 'disallows soft_delete!' do
        post = Post.create!(title: 'Post', tenant: account_1)
        expect { post.soft_delete! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_user_method and current_tenant_method both returned nil/
        )
      end

      it 'disallows restore! and direct undo_log.restore!' do
        expect { deleted_post.restore! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_user_method and current_tenant_method both returned nil/
        )

        undo_log = deleted_post.send(:find_latest_undo_log_item).undo_log
        expect { undo_log.restore! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_user_method and current_tenant_method both returned nil/
        )
      end
    end

    describe 'when current_user is null and current_tenant is ok' do
      before do
        ActiveRecord::Undo.configure do |config|
          config.current_user_method = -> {}
          config.current_tenant_method = -> { account_1 }
        end
      end

      it 'disallows soft_delete!' do
        post = Post.create!(title: 'Post', tenant: account_1)
        expect { post.soft_delete! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_user_method returned nil/
        )
      end

      it 'disallows restore!' do
        expect { deleted_post.restore! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_user_method returned nil/
        )
      end
    end

    describe 'when current_user is ok and current_tenant is null' do
      before do
        ActiveRecord::Undo.configure do |config|
          config.current_user_method = -> { user_a }
          config.current_tenant_method = -> {}
        end
      end

      it 'disallows soft_delete!' do
        post = Post.create!(title: 'Post', tenant: account_1)
        expect { post.soft_delete! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_tenant_method returned nil/
        )
      end

      it 'disallows restore!' do
        expect { deleted_post.restore! }.to raise_error(
          ActiveRecord::Undo::SecurityError,
          /Configured current_tenant_method returned nil/
        )
      end
    end

    describe 'when both are not null' do
      before do
        ActiveRecord::Undo.configure do |config|
          config.current_user_method = -> { user_a }
          config.current_tenant_method = -> { account_1 }
        end
      end

      it 'allows soft_delete! and restore!' do
        post = Post.create!(title: 'Post', tenant: account_1)
        undo_log = post.soft_delete!

        expect(undo_log.whodunnit).to eq(user_a)
        expect(undo_log.tenant).to eq(account_1)
        expect(post.reload.soft_deleted?).to be true

        expect { post.restore! }.not_to raise_error
        expect(post.reload.soft_deleted?).to be false
      end
    end

    describe 'when neither method is configured' do
      it 'allows soft_delete! and restore! as intended' do
        post = Post.create!(title: 'Unconfigured Context Post')
        undo_log = post.soft_delete!

        expect(undo_log.whodunnit).to be_nil
        expect(undo_log.tenant).to be_nil
        expect(post.reload.soft_deleted?).to be true

        expect { post.restore! }.not_to raise_error
        expect(post.reload.soft_deleted?).to be false
      end

      it 'allows direct undo_log.restore! as intended' do
        post = Post.create!(title: 'Unconfigured Direct Log Restore Post')
        undo_log = post.soft_delete!

        expect { undo_log.restore! }.not_to raise_error
        expect(post.reload.soft_deleted?).to be false
      end
    end
  end
end
