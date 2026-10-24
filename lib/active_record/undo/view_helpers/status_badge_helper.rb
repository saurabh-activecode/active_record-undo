# frozen_string_literal: true

module ActiveRecord
  module Undo
    module ViewHelpers
      module StatusBadgeHelper
        def undo_status_badge(target, action: :auto, **html_options)
          return nil if target.nil?

          act, status = resolve_target_action_and_status(target, action)
          return nil unless status

          classes = build_badge_classes(act, status, html_options.delete(:class))
          label = html_options.delete(:text) || status.to_s.humanize
          render_badge_tag(label, classes, html_options)
        end

        def soft_delete_status_badge(target, **html_options)
          undo_status_badge(target, action: :soft_delete, **html_options)
        end

        def restore_status_badge(target, **html_options)
          undo_status_badge(target, action: :restore, **html_options)
        end

        private

        def resolve_target_action_and_status(target, action)
          return nil if target.nil?

          case action
          when :soft_delete
            ['soft_delete', extract_target_status(target, :soft_delete_status)]
          when :restore
            ['restore', extract_target_status(target, :restore_status)]
          else
            resolve_auto_action_and_status(target)
          end
        end

        def extract_target_status(target, status_method)
          if target.respond_to?(status_method)
            target.public_send(status_method)
          elsif target.respond_to?(:status)
            target.status
          end
        end

        def resolve_auto_action_and_status(target)
          return ['restore', target.restore_status] if auto_restore_status?(target)
          return ['soft_delete', target.soft_delete_status] if auto_soft_delete_status?(target)
          return [log_action(target), target.status] if target.respond_to?(:status)

          nil
        end

        def auto_restore_status?(target)
          target.respond_to?(:restore_status) && target.restore_status.present?
        end

        def auto_soft_delete_status?(target)
          target.respond_to?(:soft_delete_status) && target.soft_delete_status.present?
        end

        def log_action(target)
          target.respond_to?(:action) ? target.action : nil
        end

        def build_badge_classes(action, status, custom_class)
          action_class = action ? "undo-#{action.to_s.tr('_', '-')}-badge" : nil
          ['undo-status-badge', action_class, "undo-status-#{status}", custom_class].compact.join(' ')
        end

        def render_badge_tag(label, classes, html_options)
          if respond_to?(:content_tag)
            content_tag(:span, label, html_options.merge(class: classes))
          else
            "<span class=\"#{classes}\">#{label}</span>"
          end
        end
      end
    end
  end
end
