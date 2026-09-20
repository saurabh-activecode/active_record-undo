# frozen_string_literal: true

module ActiveRecord
  module Undo
    class LogsController < ApplicationController
      module AsyncHandler
        private

        def async_request?
          params[:async].to_s == 'true' || request.headers['X-Undo-Async'].to_s == 'true'
        end

        def execute_async_restore_action
          tenant = resolve_current_tenant
          with_tenant_context(tenant) do
            @undo_log.restore_later!(whodunnit: resolve_whodunnit_user)
          end
        end

        def respond_with_async_restore_scheduled
          notice = 'Restoration has been scheduled and is processing.'
          respond_to do |format|
            format.html { redirect_to determine_redirect_path, notice: notice, status: :see_other }
            format.turbo_stream { render_turbo_stream_notice(notice, :accepted) }
            format.json { render json: { success: true, status: 'pending', log_id: @undo_log.id }, status: :accepted }
          end
        end

        def render_turbo_stream_notice(notice, status)
          render inline: turbo_stream_template('notice', notice),
                 content_type: 'text/vnd.turbo-stream.html',
                 status: status
        end

        def log_status_payload
          {
            id: @undo_log.id,
            action: @undo_log.action,
            status: @undo_log.status,
            soft_delete_status: @undo_log.soft_delete_status,
            restore_status: @undo_log.restore_status,
            error_message: @undo_log.error_message
          }
        end
      end
    end
  end
end
