# frozen_string_literal: true

module ActiveRecord
  module Undo
    module ModelExtension
      module TenantVerification
        private

        def verify_tenant_match!(undo_log)
          ctx = current_tenant_context
          raise_tenant_mismatch!(undo_log, 'nil') if ctx.nil?

          return if tenant_matches?(undo_log, ctx)

          ctx_info = ctx.is_a?(ActiveRecord::Base) ? "#{ctx.class.name}##{ctx.id}" : ctx.to_s
          raise_tenant_mismatch!(undo_log, ctx_info)
        end

        def tenant_matches?(undo_log, ctx)
          if ctx.is_a?(ActiveRecord::Base)
            undo_log.tenant_type == ctx.class.name && undo_log.tenant_id.to_s == ctx.id.to_s
          else
            undo_log.tenant_id.to_s == ctx.to_s
          end
        end

        def current_tenant_context
          ActiveRecord::Undo.config.current_tenant_method&.call || ActiveRecord::Undo.current_tenant
        end

        def raise_tenant_mismatch!(undo_log, ctx_info)
          raise ActiveRecord::Undo::SecurityError,
                "Tenant mismatch: log belongs to tenant #{undo_log.tenant_type}##{undo_log.tenant_id}, " \
                "but current context tenant is #{ctx_info}."
        end
      end
    end
  end
end
