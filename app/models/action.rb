# app/models/action.rb
class Action < ApplicationRecord
  has_paper_trail
  include AiModels

  belongs_to :step, inverse_of: :actions
  validates :title, :description, :artifact_name, presence: true

  has_one :ai_action, dependent: :destroy
  accepts_nested_attributes_for :ai_action
  attr_accessor :workflow_execution

  after_save :set_rag_query, if: :saved_sync_rag_searcher?

  def rag_artifacts
    Artifact.where(code: rag_artifact_ids)
  end

  def content_artifacts
    Artifact.where(code: content_artifact_ids)
  end

  def rag_artifact_ids
    rag_searcher["rag_artifacts"] || []
  end

  def content_artifact_ids
    rag_searcher["content_artifacts"] || []
  end

  def rag_artifact_ids=(ids)
    self.rag_searcher["rag_artifacts"] = ids.reject(&:blank?)
  end

  def content_artifact_ids=(ids)
    self.rag_searcher["content_artifacts"] = ids.reject(&:blank?)
  end

  def last_action?
    step.actions.order(:order).last == self
  end

  def very_first_action?
    self == self.step.workflow.ordered_actions.first
  end

  def very_last_action?
    self == self.step.workflow.ordered_actions.last
  end

  def first_action?
    step.actions.order(:order).first == self
  end

  def prompt_generator(workflow_execution)
    begin
      self.workflow_execution = workflow_execution
      pinecones_results = get_pinecone_results

      # Remove blocos SEARCHER do conteúdo
      self.content = content.gsub(/<<SEARCHER>>(.+?)<<SEARCHER>>/m, "").strip

      prompt = <<-MARKDOWN
You are an input filler.
Your task is to replace the inputs, question, or instruction enclosed in double braces syntax {{inputs, question or instruction}} inside the TEMPLATE.

Rules:
  - The TEMPLATE must not be modified in any way other than replacing the {{inputs}}.
  - Priority for replacements:
      1. Use exclusively the data provided in RAG DATA whenever corresponding information exists.
      2. If the corresponding information does not exist in the RAG DATA, then use your own knowledge and reasoning, considering the full context of the TEMPLATE, to insert the most accurate and contextually relevant information.
  - UNDER NO CIRCUMSTANCE should you replace any content that is not specifically enclosed within double braces {{input}}.
  - Placeholders may appear wrapped in Markdown formatting (e.g., **{{input}}**, *{{input}}*, __{{input}}__).
    Replace only the {{input}} inside and preserve the surrounding formatting exactly.
  - The final output must be the TEMPLATE with the inputs replaced.
  - The TEMPLATE is provided between <<<TEMPLATE>>> and <<<END TEMPLATE>>>.
  - The RAG DATA is provided between <<<RAG DATA>>> and <<<END RAG DATA>>>.

<<<TEMPLATE>>>#{self.content}<<<END TEMPLATE>>>

<<<RAG DATA>>>#{pinecones_results}<<<END RAG DATA>>>
    MARKDOWN

      gpt5 = Ai::Model::Gpt5.new
      result = gpt5.ask(prompt, self, force_minimal_effort: true)
      return self.content unless result[:text]
      result[:text]
    rescue Exception => e
      Rails.logger.error "❌ Prompt Generator Error: #{e.class} - #{e.message}"
    end
  end

  def parse_searcher_block
    result = Hash.new { |h, k| h[k] = [] }

    # Extrai tudo que está dentro do bloco <<SEARCHER>>...<<SEARCHER>>
    searcher_content = self.rag_query[/<<SEARCHER>>([\s\S]*?)<<SEARCHER>>/m, 1]
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

  def get_pinecone_results
    # Extrai o miolo entre os delimitadores em array
    searcher = parse_searcher_block
    pinecone_prompts = searcher[:prompt_generators]
    rag_prompts = build_pinecone_prompt(pinecone_prompts)

    pinecones_results = []
    rag_prompts.each do |rag_prompt|
      pinecones_results << workflow_execution.search_related_in_pinecone(rag_prompt, top_k: 15, artifacts: searcher[:artifacts])&.map { |r| r[:text] }&.join('\n\n')
    end
    pinecones_results = pinecones_results&.uniq&.join("\n\n")

    contents = get_contents

    pinecones_results.to_s + "\n\n---\n\n" + contents.to_s
  end

  def client(default_attribute = :name)
    workflow_execution&.client&.send(default_attribute)
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

  def saved_sync_rag_searcher?
    saved_change_to_content? || saved_change_to_rag_searcher?
  end

  def execution_artifact(execution)
    execution.artifacts.where("title = ?", "#{self.artifact_name} (EXECUTION ##{execution.id})")&.first
  end

  def set_rag_query
    if (self.has_ai_action or self.has_prompt_generator) and (self.content_artifact_ids.any? or self.rag_artifact_ids.any?)
      artifacts = self.rag_artifact_ids&.map { |title| "<<ARTIFACT>>#{title}<<ARTIFACT>>" }&.join("\n")
      contents = self.content_artifact_ids&.map { |title| "<<CONTENT>>#{title}<<CONTENT>>" }&.join("\n")
      query = <<-string
        <<SEARCHER>>
          #{mount_prompt_generator}

          #{mount_prompt}

          #{artifacts}

          #{contents}
        <<SEARCHER>>
      string

      self.update(rag_query: query)
    end
  end

  def prompt_query
    query = <<-markdown
      You are an assistant that converts **project/task prompts** into **Pinecone search instructions** using a fixed template.

      ## Task
      1. Read and analyze the entire prompt provided by the user.
      2. Identify all **explicit input fields** (placeholders strictly formatted as `[ ]`).
      3. Analyze the **semantic context** of the instructions to detect:
        - **Implicit data needs** not marked as placeholders.
        - **Technical knowledge requirements** necessary to perform the task.
      4. Transform each identified data need or technical knowledge requirement into a **clear question**.

      ## Output
      - The output must be **ONLY the list of questions**.
      - Questions must be written **in English**.
      - Do not mention or reference the identified inputs. Output must contain **only the plain questions**.
    markdown
    query
  end

  def prompt_generator_query
    query = <<-markdown
      You are an assistant that converts **project/task prompts** into **Pinecone search instructions** using a fixed template.

      ## Task
      1. Read and analyze the entire prompt provided by the user.
      2. Identify all **explicit input fields** (placeholders strictly formatted as `{{ }}`).
      3. Detect any **essential implicit data needs** (like date, sources, markets) required to complete the task, even if not marked as placeholders.
      4. Convert each identified need (explicit or implicit) into a **direct question in English**.

      ## Output
      - Output must be **ONLY the list of questions**.
      - Questions must be written **in English**.
      - Do **NOT** mention or reference placeholders or inputs directly.
      - Keep the questions **simple and direct** (e.g., *What is client's brand name?*).
      - Do **NOT** generate complex or analytical questions.
    markdown

    query
  end

  def mount_prompt_generator
    gpt5nano = Ai::Model::Gpt5Nano.new
    generator_result = gpt5nano.ask(self.content, self, system_message: prompt_generator_query)
    result_text = <<-STRING
      <<PROMPT-GENERATOR>>
        #{generator_result[:text]}
      <<PROMPT-GENERATOR>>
    STRING
    result_text
  end

  def mount_prompt
    gpt5nano = Ai::Model::Gpt5Nano.new
    generator_result = gpt5nano.ask(self.content, self, system_message: prompt_query)
    result_text = <<-STRING
      <<PROMPT>>
        #{generator_result[:text]}
      <<PROMPT>>
    STRING
    result_text
  end
end
