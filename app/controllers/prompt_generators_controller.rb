class PromptGeneratorsController < ApplicationController
  before_action :set_action
  before_action :set_workflow_execution

  def create
    # Enfileira job em background
    PromptGeneratorJob.perform_later(
      @action.id,
      @workflow_execution.id,
      current_user.id
    )

    render json: {
      status: "processing",
      message: "Prompt being generated..."
    }
  end

  private

  def set_action
    @action = Action.find(params[:action_id])
  end

  def set_workflow_execution
    @workflow_execution = WorkflowExecution.find(params[:workflow_execution_id])
  end
end
