class AiAction < ApplicationRecord
  has_paper_trail
  belongs_to :action
  before_save :normalize_custom_attributes

  private

  def normalize_custom_attributes
    if custom_attributes.is_a?(String)
      begin
        parsed = JSON.parse(custom_attributes)
        self.custom_attributes = parsed if parsed.is_a?(Hash)
      rescue JSON::ParserError
      end
    end
  end

end
