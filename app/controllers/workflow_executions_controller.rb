class WorkflowExecutionsController < ApplicationController
  before_action :set_client, :set_workflow
  before_action :set_execution, only: [ :show, :update, :destroy ]

  def index
    @executions = @client.workflow_executions.order(created_at: :desc)
  end

  def new
    @execution = @client.workflow_executions.new
  end

  def create
    @execution = @client.workflow_executions.new(execution_params)
    @execution.user = current_user
    @execution.status = :pending
    @execution.started_at = Time.current

    # seta a primeira action do workflow como ponto inicial
    first_action = @execution.workflow.steps.order(:order).first&.actions&.order(:order)&.first
    @execution.current_action = first_action if first_action

    if @execution.save
      redirect_to client_workflow_execution_path(@client, @execution), notice: "Execution started!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @workflow_execution_event = WorkflowExecutionEvent.new(action_id: @execution.current_action_id)
  end

  def update
    case params[:commit]
    when "Next"
      @execution.update!(status: :running)
      flash[:notice] = "Advanced to next action."
    when "Skip"
      flash[:alert] = "Action skipped."
    when "Abort"
      @execution.update!(status: :cancelled, finished_at: Time.current)
      flash[:alert] = "Execution aborted."
    end

    redirect_to client_workflow_execution_path(@client, @execution)
  end

  def destroy
    @execution.destroy
    redirect_to client_workflow_executions_path(@client), alert: "Execution deleted."
  end

  private

  def set_workflow
    @workflow = Workflow.find_by(title: "BAIA")
  end

  def set_client
    @client = Client.find(params[:client_id])
  end

  def set_execution
    @execution = @client.workflow_executions.find(params[:id])
  end

  def execution_params
    params.require(:workflow_execution).permit(:workflow_id)
  end
end
