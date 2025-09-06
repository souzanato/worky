# app/models/step.rb
class Step < ApplicationRecord
  has_paper_trail
  belongs_to :workflow, inverse_of: :steps
  has_many :actions, -> { order(:order) }, inverse_of: :step, dependent: :destroy
  accepts_nested_attributes_for :actions, allow_destroy: true

  validates :title, presence: true

  def next_step
    steps = workflow.steps.order(:order)
    next_step_index = steps.to_a.index(self) + 1
    return self if (next_step_index + 1) > steps.count

    steps[next_step_index]
  end
end
