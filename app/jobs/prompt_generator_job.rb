class PromptGeneratorJob < ApplicationJob
  queue_as :default

  def perform(action_id, workflow_execution_id, user_id)
    action = Action.find(action_id)
    workflow_execution = WorkflowExecution.find(workflow_execution_id)

    begin
      # Gera o prompt (pode demorar 5 minutos)
      prompt = action.prompt_generator(workflow_execution)

      # Envia resultado via Turbo Stream
      Turbo::StreamsChannel.broadcast_replace_to(
        "prompt_#{user_id}",
        target: "monaco-content-action-#{action_id}",
        partial: "prompt_generators/success",
        locals: {
          prompt: prompt,
          action_id: action_id,
          workflow_execution_id: workflow_execution_id
        }
      )

    rescue StandardError => e
      # Envia erro via Turbo Stream
      Turbo::StreamsChannel.broadcast_replace_to(
        "prompt_#{user_id}",
        target: "monaco-content-action-#{action_id}",
        partial: "prompt_generators/error",
        locals: {
          error: e.message,
          action_id: action_id
        }
      )
    end
  end
end
