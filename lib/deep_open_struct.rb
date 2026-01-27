
# frozen_string_literal: true

require "ostruct"

module DeepOpenStruct
  module_function

  # Converte Hash/Array recursivamente para OpenStruct
  def convert(obj)
    case obj
    when Hash
      OpenStruct.new(
        obj.transform_values { |v| convert(v) }
      )
    when Array
      obj.map { |v| convert(v) }
    else
      obj
    end
  end
end
