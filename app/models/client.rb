class Client < ApplicationRecord
  has_paper_trail
  validates :name, :description, :email, presence: true
  has_many :workflow_executions

  include SearchableInPinecone
  has_many :artifacts, as: :resource, dependent: :destroy
end
