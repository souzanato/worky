class WorkflowExecutionEventsController < ApplicationController
  include SseStreaming  # ← ADICIONAR esta linha

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

  def stream
    stream_response do |sse|
      # Recebe dados do POST (já vem como hash do Rails)
      event_data = params[:workflow_execution_event] || {}

      sse.write({ progress: 10, message: "Starting processing..." }, event: "status")

      # Criar evento
      @event = @execution.events.build(
        action_id: event_data[:action_id],
        input_data: event_data[:input_data],
        step_action: event_data[:step_action]
      )

      case event_data[:step_action]
      when "prompt_it"
        stream_prompt_action(sse)
      when "skip"
        skip_action(sse)
      when "next"
        stream_next_action(sse)
      when "previous"
        stream_previous_action(sse)
      else
        stream_default_action(sse)
      end
    end
  end

private

# Adicione este método para permitir os parâmetros
def event_params
  params.require(:workflow_execution_event).permit(
    :action_id,
    :input_data,
    :step_action
  )
end

  private

  def skip_action(sse)
    ordered_actions = @event.workflow_execution.workflow.ordered_actions
    next_action_index = ordered_actions.index(@event.action) + 1
    next_action = ordered_actions[next_action_index]
    @event.workflow_execution.update(current_action_id: next_action.id)
    sse.write({ progress: 50, message: "Skipping..." }, event: "status")
    sleep 3
    sse.write({ progress: 100, message: "Skipped..." }, event: "status")
    sleep 2
    sse.write({

        redirect_url: client_workflow_execution_path(@client, @execution),
        action: "reload_page"
      }, event: "complete")
  end

  def stream_prompt_action(sse)
    sse.write({ progress: 30, message: "Processing prompt..." }, event: "status")

    if @event.save
      @event.prompting = true
      @event.create_artifact_with_stream(sse)
      # O callback create_artifact da model vai processar (pode demorar)

      sse.write({ progress: 100, message: "Artifact generated!" }, event: "status")
      sse.write({
        redirect_url: client_workflow_execution_path(@client, @execution),
        action: "reload_page"
      }, event: "complete")
    else
      sse.write({ error: @event.errors.full_messages.join(", ") }, event: "error")
    end
  end

  def stream_next_action(sse)
    sse.write({ progress: 25, message: "Advancing to next step..." }, event: "status")

    if @event.save
      unless @event.skip_artifact_create?
        @event.create_artifact_with_stream(sse)
      end

      advance_execution!(@event)
      sse.write({ progress: 100, message: "Next step loaded!" }, event: "status")
      sse.write({
        redirect_url: client_workflow_execution_path(@client, @execution)
      }, event: "complete")
    else
      sse.write({ error: @event.errors.full_messages.join(", ") }, event: "error")
    end
  end

  def stream_previous_action(sse)
    sse.write({ progress: 50, message: "Returning to previous step..." }, event: "status")

    if @event.save
      step_back_execution!(@event)
      sse.write({ progress: 100, message: "Previous step loaded!" }, event: "status")
      sse.write({
        redirect_url: client_workflow_execution_path(@client, @execution)
      }, event: "complete")
    else
      sse.write({ error: @event.errors.full_messages.join(", ") }, event: "error")
    end
  end

  def stream_default_action(sse)
    sse.write({ progress: 50, message: "Saving event..." }, event: "status")

    if @event.save
      sse.write({ progress: 100, message: "Event saved!" }, event: "status")
      sse.write({
        redirect_url: client_workflow_execution_path(@client, @execution)
      }, event: "complete")
    else
      sse.write({ error: @event.errors.full_messages.join(", ") }, event: "error")
    end
  end

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
    event.action_artifact.upsert_to_pinecone
  end

  def step_back_execution!(event)
    current_action = event.action

    ordered_actions = current_action.step.workflow.ordered_actions
    current_action_index = ordered_actions.index(current_action)

    previous_action = ordered_actions[current_action_index-1]
    artifact = current_action.execution_artifact(@execution)
    previous_artifact = previous_action.execution_artifact(@execution)

    @execution.update_columns(current_action_id: previous_action&.id, status: :running) if previous_action

    previous_event = @execution.events.where(action_id: previous_action&.id)&.last
    previous_event.nil? ? event.update!(status: 0) : previous_event.update_column(:status, 0)

    event.destroy
    artifact.destroy unless artifact.nil?
    previous_artifact.destroy unless previous_artifact.nil?
  end
end
