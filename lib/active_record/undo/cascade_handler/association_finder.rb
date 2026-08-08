# lib/active_record/undo/cascade_handler/association_finder.rb
# frozen_string_literal: true

module ActiveRecord
  module Undo
    class CascadeHandler
      module AssociationFinder
        private

        def associations_to_cascade
          @record.class.reflections.values.select do |reflection|
            %i[destroy soft_delete delete_all].include?(reflection.options[:dependent])
          end
        end

        def associated_records_for(reflection)
          target = @record.public_send(reflection.name)
          return [] if target.nil?

          target.is_a?(Enumerable) ? target : [target]
        end
      end
    end
  end
end
