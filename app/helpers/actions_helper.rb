module ActionsHelper
  def custom_attributes_initial_value(initial_value)
    unless initial_value&.empty? or initial_value&.blank?
      return JSON.pretty_generate(initial_value)
    else
      return <<~JSON
      {
        "messages": [
          { "role": "user", "content": "<<prompt>>" }
        ]
      }
      JSON
    end
  end
end
