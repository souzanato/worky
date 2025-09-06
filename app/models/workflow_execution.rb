# app/models/workflow_execution.rb
class WorkflowExecution < ApplicationRecord
  belongs_to :client
  belongs_to :user
  belongs_to :workflow
  belongs_to :current_action, class_name: "Action", optional: true

  has_many :events,
           class_name: "WorkflowExecutionEvent",
           dependent: :destroy,
           inverse_of: :workflow_execution

  enum :status, { pending: 0, running: 1, completed: 2, failed: 3, cancelled: 4 }, prefix: true

  include SearchableInPinecone
  has_many :artifacts, as: :resource, dependent: :destroy

  def started_finished_message
    return "No start date available" unless self.started_at.present?

    # Nome do usuário
    user_name = self.user.first_name

    # Frase de início
    start_str = self.started_at.strftime("Started by #{user_name}, %A, %B %d, %Y, at %H:%M")

    # Caso finished_at esteja presente
    if self.finished_at.present?
      finish_str = self.finished_at.strftime("Finished on %A, %B %d, at %H:%M")
      "#{start_str}. #{finish_str}."
    else
      "#{start_str}."
    end
  end


  # Helpers
  def start!
    update!(status: :running, started_at: Time.current)
  end

  def finish!(result: :completed)
    update!(status: result, finished_at: Time.current)
  end

  def progress
    # lógica de progresso comentada
  end

  def related_artifacts
    Artifact.where("
      (resource_type = 'Client' and resource_id = #{self.client_id}) or
      (resource_type = 'Workflow' and resource_id = #{self.workflow_id}) or
      (resource_type = 'WorkflowExecution' and resource_id = #{self.id})
    ")
  end

  # 🔎 Busca abrangente no Pinecone (Client + Workflow + Execution)
  def search_related_in_pinecone(query, top_k: 15, min_score: nil, artifacts: [])
    if artifacts.blank?
      filter = {
        "$or" => [
          { "resource_type" => { "$eq" => "Client" }, "resource_id" => { "$eq" => client_id } },
          { "resource_type" => { "$eq" => "Workflow" }, "resource_id" => { "$eq" => workflow_id } },
          { "resource_type" => { "$eq" => "WorkflowExecution" }, "resource_id" => { "$eq" => id } }
        ]
      }
    else
      filter = {
        "$and" => [
          {
            "$or" => [
              { "resource_type" => { "$eq" => "Client" }, "resource_id" => { "$eq" => client_id } },
              { "resource_type" => { "$eq" => "Workflow" }, "resource_id" => { "$eq" => workflow_id } },
              { "resource_type" => { "$eq" => "WorkflowExecution" }, "resource_id" => { "$eq" => id } }
            ]
          },
          { "title" => { "$in" => artifacts + artifacts.map { |a| "#{a} (EXECUTION ##{self.id})" } } }
        ]
      }
    end

    Rails.logger.info "🔍 Pinecone Filter: #{filter.to_json}"

    searcher = Pinecone::Searcher.new
    results = searcher.search(query, top_k: top_k, filter: filter)
    results = results.select { |r| r[:score] >= min_score } if min_score
    results
  end
end
