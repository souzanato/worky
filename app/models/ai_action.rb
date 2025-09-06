class AiAction < ApplicationRecord
  has_paper_trail
  belongs_to :action
end
