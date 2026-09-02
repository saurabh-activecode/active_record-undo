# lib/active_record/undo/model_extension.rb
# frozen_string_literal: true

require_relative 'cascade_handler'
require_relative 'model_extension/attribution_helper'
require_relative 'model_extension/tenant_verification'

module ActiveRecord
  module Undo
    module ModelExtension
      extend ActiveSupport::Concern

      module ClassMethods
        # Accept a custom column parameter, defaulting to :deleted_at
        def acts_as_undoable(column: :deleted_at)
          include InstanceMethods

          define_undo_attributes!(column)
          define_undo_scopes!

          ActiveRecord::Undo.registered_models << self
        end

        private

        def define_undo_attributes!(column)
          class_attribute :undoable_column
          self.undoable_column = column.to_sym
        end

        def define_undo_scopes!
          define_basic_scopes!
          define_expired_scope!
        end

        def define_basic_scopes!
          scope :kept, -> { where(undoable_column => nil) }
          scope :soft_deleted, -> { where.not(undoable_column => nil) }
        end

        def define_expired_scope!
          scope :expired, lambda {
            period = ActiveRecord::Undo.config.retention_period
            if period
              where("#{table_name}.#{undoable_column} < ?", Time.current - period)
            else
              none
            end
          }
        end
      end

      module InstanceMethods
        include AttributionHelper
        include TenantVerification

        def soft_deleted?
          public_send(self.class.undoable_column).present?
        end

        def expired?
          return false unless soft_deleted?

          period = ActiveRecord::Undo.config.retention_period
          return false unless period

          timestamp = public_send(self.class.undoable_column)
          timestamp && timestamp < Time.current - period
        end

        def undoable?
          return false unless soft_deleted?

          ActiveRecord::Undo::UndoLogItem.joins(:undo_log).exists?(
            item_type: self.class.name,
            item_id: id
          )
        end

        def soft_delete!(whodunnit: nil, tenant: nil)
          ensure_undoable_column_exists!
          return false if soft_deleted?

          ActiveRecord::Undo.verify_configured_context!
          attrs = build_undo_log_attributes(whodunnit, tenant)
          execute_soft_delete!(attrs)
        end

        # rubocop:disable Naming/PredicateMethod
        def restore!(whodunnit: nil)
          ensure_undoable_column_exists!
          return false unless soft_deleted?

          ActiveRecord::Undo.verify_configured_context!
          log_item = find_latest_undo_log_item
          log_item ? restore_from_log!(log_item.undo_log, whodunnit) : direct_restore!

          reload
          true
        end
        # rubocop:enable Naming/PredicateMethod

        private

        def ensure_undoable_column_exists!
          column_name = self.class.undoable_column
          return if self.class.column_names.include?(column_name.to_s)

          raise ActiveRecord::Undo::Error,
                "The configured soft-delete column '#{column_name}' " \
                "does not exist on table '#{self.class.table_name}'."
        end

        def find_latest_undo_log_item
          ActiveRecord::Undo::UndoLogItem
            .where(item: self)
            .order(created_at: :desc)
            .first
        end

        def soft_delete_cascade_internal!(timestamp, undo_log)
          CascadeHandler.new(self).soft_delete_with_cascade!(timestamp, undo_log)
        end

        def execute_soft_delete!(attrs)
          transaction do
            undo_log = ActiveRecord::Undo::UndoLog.create!(attrs)
            soft_delete_cascade_internal!(Time.current, undo_log)
            undo_log.save!
            undo_log
          end
        end

        def restore_from_log!(undo_log, whodunnit)
          verify_tenant_match!(undo_log) if undo_log_tenant_present?(undo_log)

          actor = resolve_whodunnit(whodunnit)
          with_whodunnit_context(actor) do
            undo_log.restore!
          end
        end

        def with_whodunnit_context(actor)
          orig = ActiveRecord::Undo.whodunnit
          ActiveRecord::Undo.whodunnit = actor
          yield
        ensure
          ActiveRecord::Undo.whodunnit = orig
        end

        def undo_log_tenant_present?(undo_log)
          undo_log && (undo_log.tenant_id.present? || undo_log.tenant_type.present?)
        end

        def direct_restore!
          column_name = self.class.undoable_column
          update_columns(column_name => nil, updated_at: Time.current)
        end
      end
    end
  end
end
