# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Purger
      class << self
        def purge_expired!(batch_size: 1000)
          purge_expired_logs!(batch_size)
          purge_expired_records!(batch_size)
        end

        private

        def purge_expired_logs!(batch_size)
          loop do
            scope = UndoLog.expired
            ctx_tenant = ActiveRecord::Undo.config.current_tenant_method&.call
            ctx_tenant ||= ActiveRecord::Undo.current_tenant
            if ctx_tenant
              scope = if ctx_tenant.is_a?(ActiveRecord::Base)
                        scope.where(tenant_type: ctx_tenant.class.name, tenant_id: ctx_tenant.id)
                      else
                        scope.where(tenant_id: ctx_tenant)
                      end
            end

            log_ids = scope.limit(batch_size).pluck(:id)
            break if log_ids.empty?

            UndoLogItem.where(undo_log_id: log_ids).delete_all
            UndoLog.where(id: log_ids).delete_all
          end
        end

        def purge_expired_records!(batch_size)
          period = ActiveRecord::Undo.config.retention_period
          return unless period

          ActiveRecord::Undo.undoable_models.each do |model|
            purge_model_expired_records!(model, batch_size)
          end
        end

        def purge_model_expired_records!(model, batch_size)
          primary_key = model.primary_key
          loop do
            scope = model.expired
            ctx_tenant = ActiveRecord::Undo.config.current_tenant_method&.call
            ctx_tenant ||= ActiveRecord::Undo.current_tenant
            if ctx_tenant
              if model.column_names.include?('tenant_id')
                tenant_val = ctx_tenant.is_a?(ActiveRecord::Base) ? ctx_tenant.id : ctx_tenant
                scope = scope.where(tenant_id: tenant_val)
                if model.column_names.include?('tenant_type') && ctx_tenant.is_a?(ActiveRecord::Base)
                  scope = scope.where(tenant_type: ctx_tenant.class.name)
                end
              elsif model.reflect_on_association(:tenant)
                scope = scope.where(tenant: ctx_tenant)
              end
            end

            expired_ids = scope.limit(batch_size).pluck(primary_key)
            break if expired_ids.empty?

            purge_records_with_cascade!(model, expired_ids, batch_size)
          end
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

        def nullify_reflections(model)
          model.reflections.values.select do |ref|
            %i[has_many has_one].include?(ref.macro) &&
              ref.options[:dependent] == :nullify &&
              foreign_key_nullable?(ref)
          end
        end

        def cascade_reflections(model)
          model.reflections.values.select do |ref|
            next false unless %i[has_many has_one].include?(ref.macro)

            dependent = ref.options[:dependent]
            %i[destroy soft_delete delete_all].include?(dependent) ||
              non_nullable_nullify?(ref)
          end
        end

        def non_nullable_nullify?(ref)
          ref.options[:dependent] == :nullify && !foreign_key_nullable?(ref)
        end

        def foreign_key_nullable?(ref)
          column = ref.klass.columns_hash[ref.foreign_key.to_s]
          column.nil? || column.null
        end
      end
    end
  end
end
