class Artifact < ApplicationRecord
  has_paper_trail
  belongs_to :resource, polymorphic: true, optional: true
  has_one_attached :file

  # ⚡ flag interna pra evitar loop de callback
  attr_accessor :skip_markdown_callback, :result

  # 🔹 Só dispara se content ou file mudarem
  # after_commit :upsert_to_pinecone, on: %i[update], if: :pinecone_relevant_change?
  after_commit :delete_from_pinecone, on: :destroy
  after_save :generate_markdown_file, if: :should_generate_markdown_file?

  validates :code, presence: true, uniqueness: true
  before_validation :generate_code, on: :create
  after_commit :extract_file_content, on: :create

  after_update :change_action_title_references, if: :saved_change_to_title?

  def content_to_markdown!
    begin
      gpt = Ai::Model::Gpt5.new
      system_message = <<~MARKDOWN
        You are a strict text-to-markdown converter.#{'  '}
        Your ONLY task is to transform input text into **well-structured, valid Markdown syntax**.#{'  '}

        ### Rules:
        1. **Do not change, remove, or add any words.** Preserve the text exactly.#{'  '}
        2. **Do not summarize or paraphrase.**#{'  '}
        3. Interpret the structure of the text and apply proper Markdown syntax:#{'  '}
          - Use `#`, `##`, `###`, `####` for titles, sections, and subsections.#{'  '}
          - When a line follows the pattern `Label: content`, convert it into a bullet point with the **label in bold**, keeping the content exactly as is.#{'  '}
          - Convert enumerations and lists into Markdown lists.#{'  '}
          - Use `**bold**`, *italic*, or `inline code` where it improves Markdown readability, but without altering the wording.#{'  '}
        4. If the input already contains Markdown, preserve it but normalize inconsistent or broken syntax.#{'  '}
        5. Follow the best practices and formatting conventions from the Google Documentation Style Guide: https://google.github.io/styleguide/docguide/style.md#{'  '}
        6. Output must be **only the original text expressed in valid, clean Markdown** — no explanations or extra text.#{'  '}

        ### Output:
        Return exclusively the input text, unchanged in wording, but formatted with proper Markdown syntax.
      MARKDOWN

      response = gpt.ask(self.content, nil, system_message: system_message)&.dig(:text)

      if response.present?
        if persisted?
          self.skip_markdown_callback = true # 🚫 evita loop
          update!(content: response)
          # upsert_to_pinecone
        else
          self.content = response
        end
      end
    rescue Exception => e
      response = ""
    end

    response
  end

  def clean_title
    return title if title.blank?
    title.gsub(/\s*\(EXECUTION\s*#\d+\)\s*$/, "").strip
  end

  def safe_filename
    return code.downcase unless title.present?

    title
      .gsub(/[()#]/, "")          # remove parênteses e #
      .gsub(/\s+/, "-")           # troca espaços por hífen
      .gsub(/-+/, "-")            # evita hífens duplos
      .downcase
  end

  def change_action_title_references
    old_title, new_title = saved_change_to_title
    Action.where("content like ?", "%#{old_title}%").each do |a|
      new_content = a.content.gsub(old_title, new_title)
      a.update(content: new_content)
    end
  end

  def extract_file_content
    return unless file.attached? && content.blank?
    return unless file.content_type&.start_with?("text/")

    begin
      update_column(:content, file.download.force_encoding("UTF-8"))
    rescue ActiveStorage::FileNotFoundError
      Rails.logger.warn("Arquivo não encontrado ainda para Artifact #{id}")
    end
  end

  def should_generate_markdown_file?
    return false unless content.present? && saved_change_to_content?

    if saved_change_to_id? # 🚀 é create
      !file.attached?
    else # 🚀 é update
      true
    end
  end

  def generate_code
    self.code ||= "ART-#{SecureRandom.hex(4).upcase}"
  end

  # 🚀 Gera arquivo .md a partir do content convertido
  def generate_markdown_file
    return if skip_markdown_callback # 🚫 evita loop infinito

    markdown = content_to_markdown!
    return if markdown.blank?

    filename = "#{code.parameterize}.md"
    file.attach(
      io: StringIO.new(markdown),
      filename: filename,
      content_type: "text/markdown"
    )
  end

  def upsert_to_pinecone
    text = canonical_text
    return if text.blank?

    metadata = {
      code: code,
      title: title,
      content: content,
      description: description,
      filename: (file.filename.to_s if file.attached?),
      resource_type: resource_type,
      resource_id: resource_id
    }.compact

    Pinecone::Chunker.new.process_document(
      text,
      document_id: pinecone_id,
      metadata: metadata
    )
  rescue => e
    Rails.logger.error("Pinecone upsert failed: #{e.class} - #{e.message}")
  end

  def delete_from_pinecone
    pinecone = ::Pinecone::Client.new
    index = pinecone.index(host: Settings.reload!.apis.pinecone.host)
    index.delete(ids: [ pinecone_id ], namespace: "artifacts")
  rescue => e
    Rails.logger.error("Pinecone delete failed: #{e.class} - #{e.message}")
  end

  def pinecone_id
    "artifact-#{id}"
  end

  def canonical_text
    return content if content.present?
    return file.download.force_encoding("UTF-8") if file.attached? && file.content_type&.start_with?("text/")
    title.presence || code
  end

  # 🔹 Só sobe pro Pinecone se realmente teve mudança relevante
  def pinecone_relevant_change?
    saved_change_to_content? || (previous_changes.key?("updated_at") && file.attached?)
  end
end
