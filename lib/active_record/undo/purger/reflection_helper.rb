# frozen_string_literal: true

module ActiveRecord
  module Undo
    class Purger
      module ReflectionHelper
        private

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
