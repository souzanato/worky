class WorkflowExecutionEvent < ApplicationRecord
  has_paper_trail
  belongs_to :workflow_execution, inverse_of: :events
  belongs_to :action
  # after_create :create_artifact

  validates :workflow_execution, :action, presence: true

  # input_data / output_data armazenam o que entrou e o que saiu
  store_accessor :input_data
  store_accessor :output_data

  attr_accessor :step_action, :prompting

  def client(default_attribute = :name)
    workflow_execution&.client&.send(default_attribute)
  end

  def action_artifact
    workflow_execution.artifacts.where(title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})")&.last
  end


  def substituir_placeholders(hash, placeholders, prompt)
    hash.transform_values do |valor|
      case valor
      when Hash
        substituir_placeholders(valor, placeholders, prompt)
      when Array
        valor.map { |item| item.is_a?(Hash) ? substituir_placeholders(item, placeholders, prompt) : substituir_valor(item, placeholders) }
      else
        substituir_valor(valor, placeholders, prompt)
      end
    end
  end

  def substituir_valor(valor, placeholders, prompt)
    placeholders.each do |p|
      if valor == p[:placeholder]
        if p[:placeholder] == "<<prompt>>"
          return prompt
        else
          return p[:replacement]
        end
      end
    end
    valor
  end

  def custom_attributes_placeholders
    [
      { placeholder: "<<prompt>>", replacement: "prompt" }
    ]
  end

  def create_artifact_with_stream(sse)
    unless skip_artifact_create?
      unless self.action.has_ai_action
        sse.write({ progress: 75, message: "Creating artifact..." }, event: "status")
        artifact = Artifact.find_or_initialize_by(
          title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})",
          resource_type: "WorkflowExecution",
          resource_id: self.workflow_execution.id
        )

        artifact.update!(
          description: self.action.description,
          content: self.input_data
        )
      else
        sse.write({ progress: 40, message: "Loading RAG content..." }, event: "status")
        pinecone_results = set_rag_content || ""
        strip_rag_content!

        prompt = "#{self.input_data}\n\n---\n\n#REFERENCE KNOWLEDGE BASE\n\n#{pinecone_results}"

        # prompt de parametro: decisão provisoria, considerando que o prompt é procesado após a instrução de "prompt it"
        request_hash = substituir_placeholders(self.action.ai_action.custom_attributes, custom_attributes_placeholders, prompt)
        request_hash[:model] = self.action.ai_action.best_model_picker ? self.select_ai_model(sse) : self.action.ai_action.ai_model
        request_hash[:sse] = sse
        request_hash.deep_symbolize_keys!
        ai_client = Ai::OpenRouter::Assistant.new
        sse.write({ progress: 60, message: "Processing prompt with #{request_hash[:model]}..." }, event: "status")
        sleep 5
        result = ai_client.chat_completion(**request_hash)
        content = result&.dig(:choices, 0, :message, :content)

        sse.write({ progress: 75, message: "Creating artifact..." }, event: "status")
        artifact = Artifact.find_or_initialize_by(
          title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})",
          resource_type: "WorkflowExecution",
          resource_id: self.workflow_execution.id
        )

        artifact.update!(
          description: self.action.description,
          content: content
        )

        self.update(output_data: result)
      end
    else
      artifact = action_artifact
    end

    artifact
  end

  def skip_artifact_create?
    unless self.prompting == true
      self.workflow_execution.artifacts.where("title like ?", "%#{self.action.artifact_name}%").any?
    end
  end

  private

  def select_ai_model(sse)
    available_models = Ai::OpenRouter::Assistant.list_models
    ai_client = Ai::OpenRouter::Assistant.new
    sse.write({ progress: 59, message: "Selecting best model for the task..." }, event: "status")

    meta_prompt = <<~MARKDOWN
      You are an expert model router. Analyze the USER PROMPT and select EXACTLY ONE model from the MODEL LIST that best matches.

      CRITERIA (reason step-by-step internally, output ONLY the model name):
      1. Code/programming → coding-specialized models
      2. Math/reasoning → math/logic models
      3. Creative/writing → creative/general models
      4. Long context/analysis → high-context models
      5. Vision/multimodal → vision models
      6. Fast/cheap → lightweight models

      EXAMPLES:
      USER PROMPT: "Write Python code for API"
      → "gpt-4o-code"  [coding]

      USER PROMPT: "Solve 2x + 3 = 7"
      → "o1-mini"  [math]

      USER PROMPT: "Write a poem about cats"
      → "claude-3.5-sonnet"  [creative]

      USER PROMPT:
      #{self.action.content}

      MODEL LIST:
      #{available_models.map { |a| a.name }.join("\n")}
    MARKDOWN

    request_hash = { messages: [ { role: "user", content: meta_prompt } ], model: "perplexity/sonar-pro" }
    result = ai_client.chat_completion(**request_hash)
    model = result&.dig(:choices, 0, :message, :content)
    model_id = available_models.filter { |a| a&.name&.eql?(model) }&.first&.dig(:id)
    model_id
  end


  def strip_rag_content!
    return if input_data.blank?

    cleaned = input_data.gsub(/<<SEARCHER>>.*?<<SEARCHER>>/m, "").strip
    update!(input_data: cleaned)
  end

  def create_artifact
    unless self.action.has_ai_action
      artifact = Artifact.find_or_initialize_by(
        title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})",
        resource_type: "WorkflowExecution",
        resource_id: self.workflow_execution.id
      )

      artifact.update!(
        description: self.action.description,
        content: self.input_data
      )
    else
      pinecone_results = set_rag_content
      strip_rag_content!
      prompt = "#{self.input_data}\n\n---\n\n#REFERENCE KNOWLEDGE BASE\n\n#{pinecone_results}"
      ai_client = Action.find_ai_model_by_code(self.action.ai_action.ai_model).klass.new
      result = ai_client.ask(prompt, self.action, sse: sse)

      artifact = Artifact.find_or_initialize_by(
        title: "#{self.action.artifact_name} (EXECUTION ##{self.workflow_execution.id})",
        resource_type: "WorkflowExecution",
        resource_id: self.workflow_execution.id
      )

      artifact.update!(
        description: self.action.description,
        content: result[:text]
      )
    end
  end

  def parse_searcher_block
    result = result = Hash.new { |h, k| h[k] = [] }

    # Extrai tudo que está dentro do bloco <<SEARCHER>>...<<SEARCHER>>
    # searcher_content = self.input_data[/<<SEARCHER>>([\s\S]*?)<<SEARCHER>>/m, 1]
    searcher_content = self.action.rag_query[/<<SEARCHER>>([\s\S]*?)<<SEARCHER>>/m, 1]

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
    return nil if self&.action&.rag_searcher&.map { |key, value| value }&.flatten&.empty?

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
