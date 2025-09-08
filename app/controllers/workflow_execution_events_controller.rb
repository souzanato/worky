class WorkflowExecutionEventsController < ApplicationController
  before_action :set_client
  before_action :set_execution

  def create
    @event = @execution.events.build(event_params)

    if @event.save
      # atualiza execução pra apontar pro próximo passo
      advance_execution!(@event) if @event.step_action == "next"
      redirect_to client_workflow_execution_path(@client, @execution), notice: "Event recorded."
    else
      redirect_to client_workflow_execution_path(@client, @execution),
                  alert: "Could not record event."
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
    byebug
    step = event.action.last_action? ? event.action.step.next_step : event.action.step
    next_action = step.actions.where("actions.id > ?", event.action.id).first
    @execution.update!(current_action: next_action, status: :running) if next_action
  end
end
