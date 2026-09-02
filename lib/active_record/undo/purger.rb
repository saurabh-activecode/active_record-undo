# frozen_string_literal: true

require_relative 'purger/reflection_helper'

module ActiveRecord
  module Undo
    class Purger
      extend ReflectionHelper

      class << self
        def purge_expired!(batch_size: 1000)
          purge_expired_logs!(batch_size)
          purge_expired_records!(batch_size)
        end

        private

        def purge_expired_logs!(batch_size)
          loop do
            log_ids = current_tenant_log_scope.limit(batch_size).pluck(:id)
            break if log_ids.empty?

            UndoLogItem.where(undo_log_id: log_ids).delete_all
            UndoLog.where(id: log_ids).delete_all
          end
        end

        def current_tenant_log_scope
          scope = UndoLog.expired
          ctx = current_tenant_context
          return scope unless ctx

          if ctx.is_a?(ActiveRecord::Base)
            scope.where(tenant_type: ctx.class.name, tenant_id: ctx.id)
          else
            scope.where(tenant_id: ctx)
          end
        end

        def current_tenant_context
          ActiveRecord::Undo.config.current_tenant_method&.call || ActiveRecord::Undo.current_tenant
        end

        def purge_expired_records!(batch_size)
          period = ActiveRecord::Undo.config.retention_period
          return unless period

          ActiveRecord::Undo.undoable_models.each do |model|
            purge_model_expired_records!(model, batch_size)
          end
        end

        def purge_model_expired_records!(model, batch_size)
          pk = model.primary_key
          loop do
            expired_ids = scoped_model_expired(model).limit(batch_size).pluck(pk)
            break if expired_ids.empty?

            purge_records_with_cascade!(model, expired_ids, batch_size)
          end
        end

        def scoped_model_expired(model)
          scope = model.expired
          ctx = current_tenant_context
          return scope unless ctx

          apply_tenant_scope(scope, model, ctx)
        end

        def apply_tenant_scope(scope, model, ctx)
          if model.column_names.include?('tenant_id')
            apply_tenant_column_scope(scope, model, ctx)
          elsif model.reflect_on_association(:tenant)
            scope.where(tenant: ctx)
          else
            scope
          end
        end

        def apply_tenant_column_scope(scope, model, ctx)
          val = ctx.is_a?(ActiveRecord::Base) ? ctx.id : ctx
          scope = scope.where(tenant_id: val)
          if model.column_names.include?('tenant_type') && ctx.is_a?(ActiveRecord::Base)
            scope = scope.where(tenant_type: ctx.class.name)
          end
          scope
        end

        def purge_records_with_cascade!(model, record_ids, batch_size)
          return if record_ids.empty?

          nullify_dependent_associations!(model, record_ids)
          purge_cascading_associations!(model, record_ids, batch_size)
          delete_records!(model, record_ids)
        end

        def nullify_dependent_associations!(model, record_ids)
          nullify_reflections(model).each do |reflection|
            child_query_for(model, reflection, record_ids).update_all(reflection.foreign_key => nil)
          end
        end

        def purge_cascading_associations!(model, record_ids, batch_size)
          cascade_reflections(model).each do |reflection|
            query = child_query_for(model, reflection, record_ids)
            primary_key = reflection.klass.primary_key

            query.pluck(primary_key).each_slice(batch_size) do |child_ids|
              purge_records_with_cascade!(reflection.klass, child_ids, batch_size)
            end
          end
        end

        def child_query_for(model, reflection, record_ids)
          query = reflection.klass.unscoped.where(reflection.foreign_key => record_ids)
          query = query.where(reflection.type => model.name) if reflection.type
          query
        end

        def delete_records!(model, record_ids)
          model.unscoped.where(model.primary_key => record_ids).delete_all
        end
      end
    end
  end
end
