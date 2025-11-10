class AiCollectConfig < ApplicationRecord
  belongs_to :workflow
  validates :title, :code, :ai_model, presence: true
end
