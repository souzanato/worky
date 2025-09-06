# app/models/workflow.rb
class Workflow < ApplicationRecord
  has_many :steps, -> { order(:order) }, inverse_of: :workflow, dependent: :destroy
  accepts_nested_attributes_for :steps, allow_destroy: true

  validates :title, presence: true

  include SearchableInPinecone
  has_many :artifacts, as: :resource, dependent: :destroy
end
