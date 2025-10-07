# app/models/workflow.rb
class Workflow < ApplicationRecord
  has_many :steps, -> { order(:order) }, inverse_of: :workflow, dependent: :destroy
  accepts_nested_attributes_for :steps, allow_destroy: true

  validates :title, presence: true

  include SearchableInPinecone
  has_many :artifacts, as: :resource, dependent: :destroy

  def all_artifacts
    collection = self.artifacts.map { |a| a.title }
    collection << Action.joins(step: :workflow).where("workflows.id = ?", self.id).map { |c| c.artifact_name }
    collection.flatten.uniq.map { |title| OpenStruct.new(id: title, title: title) }
  end

  def ordered_actions
    Action
      .joins(step: :workflow)
      .where("workflows.id = ?", self.id)
      .order("steps.order, actions.order")
  end
end
