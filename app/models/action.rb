# app/models/action.rb
class Action < ApplicationRecord
  has_paper_trail
  include AiModels

  belongs_to :step, inverse_of: :actions
  validates :title, :description, :artifact_name, presence: true

  has_one :ai_action, dependent: :destroy
  accepts_nested_attributes_for :ai_action
  attr_accessor :workflow_execution

  def last_action?
    step.actions.order(:order).last == self
  end

  def prompt_generator(workflow_execution)
    self.workflow_execution = workflow_execution
    byebug
    pinecones_results = get_pinecone_results
    # Remove o bloco completo (incluindo START e END) do content
    self.content = content.gsub(/<<SEARCHER>>(.+?)<<SEARCHER>>/m, "").strip

    # - If no data is available for a given field, consider fullfil it using your knowledge based on what is described in the KNOWLEDGE BASE.
    prompt = <<-markdown
You are an input filler.
Your task is to use exclusively the data provided in KNOWLEDGE BASE to replace the inputs, question or instruction enclosed in double braces syntax {{inputs, question or instruction}} inside the TEMPLATE.

Rules:
  - The TEMPLATE must not be modified in any way other than replacing the {{inputs}}.
  - Each {{input}} must be replaced only if corresponding information exists in the KNOWLEDGE BASE.
  - UNDER NO CIRCUMSTANCE should you replace any content that is not specifically enclosed within double braces {{input}}.
  - The final output must be the TEMPLATE with the inputs replaced.
  - The TEMPLATE is provided between <<<TEMPLATE>>> and <<<END TEMPLATE>>>.
  - The KNOWLEDGE BASE is provided between <<<KNOWLEDGE BASE>>> and <<<END KNOWLEDGE BASE>>>.

  <<<TEMPLATE>>>#{self.content}<<<END TEMPLATE>>>

  <<<KNOWLEDGE BASE>>>#{pinecones_results}<<<END KNOWLEDGE BASE>>>
    markdown
    gpt5 = Ai::Model::Gpt5.new
    result = gpt5.ask(prompt)
    return self.content unless result[:text]
    result[:text]
  end

  def parse_searcher_block
    result = Hash.new { |h, k| h[k] = [] }

    # Extrai tudo que está dentro do bloco <<SEARCHER>>...<<SEARCHER>>
    searcher_content = self.content[/<<SEARCHER>>([\s\S]*?)<<SEARCHER>>/m, 1]

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
end
