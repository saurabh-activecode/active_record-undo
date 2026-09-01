# lib/active_record/undo/model_extension.rb
# frozen_string_literal: true

require_relative 'cascade_handler'

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

          resolved_whodunnit = whodunnit
          resolved_whodunnit ||= ActiveRecord::Undo.config.current_user_method&.call
          resolved_whodunnit ||= ActiveRecord::Undo.whodunnit

          resolved_tenant = tenant
          resolved_tenant ||= ActiveRecord::Undo.config.current_tenant_method&.call
          resolved_tenant ||= ActiveRecord::Undo.current_tenant
          resolved_tenant ||= self.tenant if respond_to?(:tenant)

          log_attrs = {}
          if resolved_whodunnit
            if resolved_whodunnit.is_a?(ActiveRecord::Base)
              log_attrs[:whodunnit] = resolved_whodunnit
            else
              log_attrs[:whodunnit_id] = resolved_whodunnit
            end
          end

          if resolved_tenant
            if resolved_tenant.is_a?(ActiveRecord::Base)
              log_attrs[:tenant] = resolved_tenant
            else
              log_attrs[:tenant_id] = resolved_tenant
            end
          end

          undo_log = nil
          timestamp = Time.current

          transaction do
            undo_log = ActiveRecord::Undo::UndoLog.create!(log_attrs)
            soft_delete_cascade_internal!(timestamp, undo_log)
            undo_log.save!
          end

          undo_log
        end

        # rubocop:disable Naming/PredicateMethod
        def restore!(whodunnit: nil)
          ensure_undoable_column_exists!
          return false unless soft_deleted?

          log_item = find_latest_undo_log_item
          if log_item
            undo_log = log_item.undo_log
            if undo_log && (undo_log.tenant_id.present? || undo_log.tenant_type.present?)
              ctx_tenant = ActiveRecord::Undo.config.current_tenant_method&.call
              ctx_tenant ||= ActiveRecord::Undo.current_tenant

              if ctx_tenant.nil?
                raise ActiveRecord::Undo::SecurityError,
                      "Tenant mismatch: log belongs to tenant #{undo_log.tenant_type}##{undo_log.tenant_id}, " \
                      'but current context tenant is nil.'
              elsif ctx_tenant.is_a?(ActiveRecord::Base)
                if undo_log.tenant_type != ctx_tenant.class.name || undo_log.tenant_id.to_s != ctx_tenant.id.to_s
                  raise ActiveRecord::Undo::SecurityError,
                        "Tenant mismatch: log belongs to tenant #{undo_log.tenant_type}##{undo_log.tenant_id}, " \
                        "but current context tenant is #{ctx_tenant.class.name}##{ctx_tenant.id}."
                end
              elsif undo_log.tenant_id.to_s != ctx_tenant.to_s
                raise ActiveRecord::Undo::SecurityError,
                      "Tenant mismatch: log belongs to tenant #{undo_log.tenant_type}##{undo_log.tenant_id}, " \
                      "but current context tenant is #{ctx_tenant}."
              end
            end

            resolved_whodunnit = whodunnit
            resolved_whodunnit ||= ActiveRecord::Undo.config.current_user_method&.call
            resolved_whodunnit ||= ActiveRecord::Undo.whodunnit

            original_whodunnit = ActiveRecord::Undo.whodunnit
            begin
              ActiveRecord::Undo.whodunnit = resolved_whodunnit
              undo_log.restore!
            ensure
              ActiveRecord::Undo.whodunnit = original_whodunnit
            end
          else
            column_name = self.class.undoable_column
            update_columns(column_name => nil, updated_at: Time.current)
          end

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

        def restore_internally!(log_item)
          if log_item
            log_item.undo_log.restore!
          else
            column_name = self.class.undoable_column
            update_columns(column_name => nil, updated_at: Time.current)
          end
        end
      end
    end
  end
end
