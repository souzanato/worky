class WorkflowExecutionEvent < ApplicationRecord
  has_paper_trail
  belongs_to :workflow_execution, inverse_of: :events
  belongs_to :action
  after_create :create_artifact

  validates :workflow_execution, :action, presence: true

  # input_data / output_data armazenam o que entrou e o que saiu
  store_accessor :input_data
  store_accessor :output_data

  def client(default_attribute = :name)
    workflow_execution&.client&.send(default_attribute)
  end

  private

  def strip_rag_content!
    return if input_data.blank?

    cleaned = input_data.gsub(/<<SEARCHER>>.*?<<SEARCHER>>/m, "").strip
    update!(input_data: cleaned)
  end

  def create_artifact
    unless self.action.has_ai_action
      Artifact.create(
        title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})",
        description: self.action.description,
        content: self.input_data,
        resource_type: "WorkflowExecution",
        resource_id: self.workflow_execution.id)
    else
      pinecone_results = set_rag_content
      strip_rag_content!
      prompt = "#{self.input_data}\n\n---\n\n#REFERENCE KNOWLEDGE BASE\n\n#{pinecone_results}"
      ai_client = Action.find_ai_model_by_code(self.action.ai_action.ai_model).klass.new
      result = ai_client.ask(prompt)

      Artifact.create(
        title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})",
        description: self.action.description,
        content: result[:text],
        resource_type: "WorkflowExecution",
        resource_id: self.workflow_execution.id)
    end
  end

  def parse_searcher_block
    result = Hash.new { |h, k| h[k] = [] }

    # Extrai tudo que está dentro do bloco <<SEARCHER>>...<<SEARCHER>>
    searcher_content = self.input_data[/<<SEARCHER>>([\s\S]*?)<<SEARCHER>>/m, 1]

    return result unless searcher_content

    # Regex para capturar tags com hífen, underscore, etc.
    searcher_content.scan(/<<([\w-]+)>>\s*([\s\S]*?)\s*<<\1>>/m).each do |tag, content|
      # Normaliza o nome da tag: converte hífen para underscore e adiciona 's'
      normalized_tag = tag.downcase.gsub("-", "_")
      key = "#{normalized_tag}s".to_sym

      cleaned_content = content.strip
      result[key] << cleaned_content unless cleaned_content.empty?
    end

    result
  end

  def get_contents
    searcher = parse_searcher_block
    available_artifacts = self.workflow_execution.related_artifacts
    matches = available_artifacts.select { |artifact| searcher[:contents].any? { |term| artifact.title.include?(term) } }
    return "" unless matches.any?
    matches.map { |m| "# #{m.title}\n\n#{m.content}" }.join("\n\n---\n\n")
  end

  def set_rag_content
    searcher = parse_searcher_block
    pinecone_prompts = build_pinecone_prompt(searcher[:prompts])
    pinecone_artifacts = searcher[:artifacts]

    pinecones_results = []
    pinecone_prompts.each do |prompt|
      pinecones_results << workflow_execution.search_related_in_pinecone(prompt, top_k: 20, artifacts: pinecone_artifacts)&.map { |r| r[:text] }&.join('\n\n')
    end
    pinecones_results = pinecones_results&.flatten&.join("\n\n")

    contents = get_contents

    pinecones_results.to_s + "\n\n---\n\n" + contents.to_s
  end

  def build_pinecone_prompt(rag_prompts_str)
    pinecone_prompts = rag_prompts_str.map do |prompt|
      prompt.gsub(/{{(.*?)}}/) do
        method_name = Regexp.last_match(1).strip

        if respond_to?(method_name)
          send(method_name).to_s
        else
          "{{#{method_name}}}" # mantém se não existir
        end
      end
    end

    pinecone_prompts
  end

  # 🔹 Método que substitui {{RAG_REFERENCE}} ou {{rag_reference}} pelo rag_result
  def substitute_rag_reference(text, rag_result)
    return text if text.blank? || rag_result.blank?

    text.gsub(/\{\{\s*RAG_REFERENCE\s*\}\}|\{\{\s*rag_reference\s*\}\}/, rag_result)
  end
end
