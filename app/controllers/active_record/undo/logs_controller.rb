# frozen_string_literal: true

module ActiveRecord
  module Undo
    class LogsController < ApplicationController
      before_action :set_undo_log
      before_action :check_not_found
      before_action :check_expired

      def restore
        return unless @undo_log

        count = @undo_log.undo_log_items.count
        execute_restore_action
        respond_with_restored_log(count)
      end

      private

      def set_undo_log
        @undo_log = find_undo_log
      end

      def check_not_found
        handle_not_found if @undo_log.nil?
      end

      def check_expired
        handle_expired if @undo_log&.expired?
      end

      def find_undo_log
        if params[:token].present?
          ActiveRecord::Undo::UndoLog.find_by_signed_token(params[:token])
        elsif params[:id].present?
          find_by_id_or_token(params[:id])
        end
      end

      def find_by_id_or_token(identifier)
        if identifier.to_s.match?(/\A\d+\z/)
          ActiveRecord::Undo::UndoLog.find_by(id: identifier)
        else
          ActiveRecord::Undo::UndoLog.find_by_signed_token(identifier)
        end
      end

      def execute_restore_action
        tenant = resolve_current_tenant
        with_tenant_context(tenant) do
          @undo_log.restore!(whodunnit: resolve_whodunnit_user)
        end
      end

      def with_tenant_context(tenant)
        orig = ActiveRecord::Undo.current_tenant
        ActiveRecord::Undo.current_tenant = tenant if tenant.present?
        yield
      ensure
        ActiveRecord::Undo.current_tenant = orig
      end

      def respond_with_restored_log(count)
        respond_to do |format|
          format.html { redirect_to determine_redirect_path, notice: 'Record successfully restored.' }
          format.turbo_stream { render_turbo_stream_success }
          format.json { render json: { success: true, restored_items_count: count }, status: :ok }
        end
      end

      def render_turbo_stream_success
        render inline: turbo_stream_template('notice', 'Record successfully restored.'),
               content_type: 'text/vnd.turbo-stream.html',
               status: :ok
      end
    end
  end
end
