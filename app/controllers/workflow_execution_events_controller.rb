class WorkflowExecutionEventsController < ApplicationController
  before_action :set_client
  before_action :set_execution

  def create
    @event = @execution.events.build(event_params)

    if @event.step_action == "next"
      advance_execution!(@event)
      redirect_to client_workflow_execution_path(@client, @execution), notice: "Event recorded."
    elsif @event.step_action == "step_back"
      step_back_execution!(@event)
      redirect_to client_workflow_execution_path(@client, @execution), notice: "Event recorded."
    else
      if @event.save
        # atualiza execução pra apontar pro próximo passo
        redirect_to client_workflow_execution_path(@client, @execution), notice: "Event recorded."
      else
        redirect_to client_workflow_execution_path(@client, @execution),
                    alert: "Could not record event."
      end
    end
  end

  private

  def set_client
    @client = Client.find(params[:client_id])
  end

  def set_execution
    @execution = @client.workflow_executions.find(params[:workflow_execution_id])
  end

  def event_params
    params.require(:workflow_execution_event).permit(:action_id, :input_data, :output_data, :step_action)
  end

  # placeholder: avança execução pro próximo action
  def advance_execution!(event)
    step = event.action.last_action? ? event.action.step.next_step : event.action.step
    next_action = step.actions.where("actions.id > ?", event.action.id).first
    @execution.update_columns(current_action_id: next_action&.id, status: :running) if next_action
    previous_event = @execution.events.where(action_id: event.action_id)&.last
    previous_event.nil? ? event.update!(status: 1) : previous_event.update_column(:status, 1)
  end

  def step_back_execution!(event)
    step = event.action.first_action? ? event.action.step.previous_step : event.action.step
    previous_action = step.actions.where("actions.id > ?", event.action.id).last
    @execution.update_columns(current_action_id: previous_action&.id, status: :running) if previous_action
    previous_event = @execution.events.where(action_id: event.action_id)&.last
    previous_event.nil? ? event.update!(status: 0) : previous_event.update_column(:status, 0)
  end
end
