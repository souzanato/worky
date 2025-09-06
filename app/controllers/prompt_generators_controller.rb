class PromptGeneratorsController < ApplicationController
  before_action :set_action
  before_action :set_workflow_execution

  def create
    begin
      prompt = @action.prompt_generator(@workflow_execution)
    rescue Exception => e
      render json: { errors: "There was an error creating the prompt generator. Error: #{e}" }, status: :unprocessable_entity
    else
      render json: { prompt: prompt }
    end
  end

  private

  def set_action
    @action = Action.find(params[:action_id])
  end

  def set_workflow_execution
    @workflow_execution = WorkflowExecution.find(params[:workflow_execution_id])
  end
end
