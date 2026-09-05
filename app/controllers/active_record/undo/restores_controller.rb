# frozen_string_literal: true

module ActiveRecord
  module Undo
    class RestoresController < LogsController
      def create
        restore
      end
    end
  end
end
