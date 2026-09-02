# frozen_string_literal: true

module ActiveRecord
  module Undo
    module ModelExtension
      module AttributionHelper
        private

        def resolve_whodunnit(whodunnit)
          whodunnit || ActiveRecord::Undo.config.current_user_method&.call || ActiveRecord::Undo.whodunnit
        end

        def resolve_tenant(tenant)
          tenant || ActiveRecord::Undo.config.current_tenant_method&.call ||
            ActiveRecord::Undo.current_tenant || (self.tenant if respond_to?(:tenant))
        end

        def build_undo_log_attributes(whodunnit, tenant)
          attrs = {}
          actor = resolve_whodunnit(whodunnit)
          assign_whodunnit_attribute!(attrs, actor) if actor

          ten = resolve_tenant(tenant)
          assign_tenant_attribute!(attrs, ten) if ten
          attrs
        end

        def assign_whodunnit_attribute!(attrs, actor)
          if actor.is_a?(ActiveRecord::Base)
            attrs[:whodunnit] = actor
          else
            attrs[:whodunnit_id] = actor
          end
        end

        def assign_tenant_attribute!(attrs, ten)
          if ten.is_a?(ActiveRecord::Base)
            attrs[:tenant] = ten
          else
            attrs[:tenant_id] = ten
          end
        end
      end
    end
  end
end
