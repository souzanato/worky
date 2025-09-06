# app/services/pinecone/chunker.rb (versão melhorada)
require "net/http"
require "json"
require "uri"

class Pinecone::Chunker
  # Configurações padrão para o chunking
  DEFAULT_CHUNK_SIZE = 1200      # Tamanho alvo de cada chunk (caracteres)
  MIN_CHUNK_SIZE = 50            # Tamanho mínimo mais flexível
  OVERLAP_SIZE = 150             # Sobreposição entre chunks para manter contexto

  def initialize(min_chunk_size: MIN_CHUNK_SIZE)
    @pinecone_api_key = Settings.reload!.apis.pinecone.api_key
    @pinecone_index_url = Settings.reload!.apis.pinecone.index_name
    @openai_api_key = Settings.reload!.apis.openai.access_token
    @min_chunk_size = min_chunk_size  # Usa o parâmetro passado

    # Validações
    raise "PINECONE_API_KEY não configurada" unless @pinecone_api_key.present?
    raise "PINECONE_INDEX_HOST não configurada" unless @pinecone_index_url.present?
    raise "OPENAI_API_KEY não configurada" unless @openai_api_key.present?
  end

  # Método principal que recebe o texto e processa tudo
  def process_document(text, document_id:, metadata: {})
    Rails.logger.info "🔄 Iniciando processamento do documento #{document_id}..."
    Rails.logger.info "📝 Texto original: #{text.length} caracteres"

    # Validações de entrada
    if text.blank?
      Rails.logger.warn "⚠️ Texto vazio fornecido"
      return { success: false, error: "Texto vazio", chunks_count: 0, document_id: document_id }
    end

    # 1. Fazer o chunking do texto
    chunks = create_chunks(text)
    Rails.logger.info "✅ Criados #{chunks.length} chunks"

    if chunks.empty?
      Rails.logger.warn "⚠️ Nenhum chunk foi criado após processamento"
      return { success: false, error: "Nenhum chunk válido criado", chunks_count: 0, document_id: document_id }
    end

    # Debug dos chunks
    chunks.each_with_index do |chunk, i|
      Rails.logger.debug "Chunk #{i}: #{chunk[:text].length} chars (#{chunk[:heading]}) - '#{chunk[:text][0..50]}...'"
    end

    # 2. Gerar embeddings para cada chunk
    embeddings_data = generate_embeddings_batch(chunks, document_id, metadata)
    Rails.logger.info "✅ Embeddings gerados para #{embeddings_data.length} chunks"

    # 3. Enviar para o Pinecone
    upload_to_pinecone(embeddings_data)
    Rails.logger.info "✅ Upload para Pinecone concluído"

    {
      success: true,
      chunks_count: chunks.length,
      document_id: document_id
    }
  rescue => e
    Rails.logger.error "❌ Erro no processamento: #{e.class.name} - #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(3).join(' | ')}"
    { success: false, error: e.message, chunks_count: 0, document_id: document_id }
  end


  private

  # Sobrescreve create_chunks para usar Markdown como primeira estratégia
  def create_chunks(text)
    return [] if text.blank?

    Rails.logger.info "Texto original: #{text.length} caracteres"

    chunks = []

    # 👉 Prioriza Markdown headings
    markdown_sections = split_by_markdown_sections(text)
    Rails.logger.info "Dividido em #{markdown_sections.length} seções Markdown"

    markdown_sections.each_with_index do |section, i|
      heading = section[:heading]
      content = section[:content]

      # sempre tenta quebrar por parágrafos, mesmo se for curto
      section_chunks = split_large_section(content)

      if section_chunks.length == 1
        # se só retornou um, mantém inteiro
        chunks << { heading: heading, text: section_chunks.first }
      else
        # se quebrou em vários, adiciona todos
        section_chunks.each do |subchunk|
          chunks << { heading: heading, text: subchunk }
        end
      end
      # if content.length <= DEFAULT_CHUNK_SIZE
      #   chunks << { heading: heading, text: content }
      # else
      #   Rails.logger.info "🔎 Seção #{i} muito grande (#{content.length} chars), quebrando internamente"
      #   split_large_section(content).each do |subchunk|
      #     chunks << { heading: heading, text: subchunk }
      #   end
      # end
    end

    # Filtra chunks muito pequenos
    valid_chunks = chunks.reject { |c| c[:text].strip.length < @min_chunk_size }

    if valid_chunks.empty? && chunks.any?
      Rails.logger.warn "Todos os chunks foram rejeitados. Relaxando filtro"
      valid_chunks = chunks.reject { |c| c[:text].strip.length < 10 }
    end

    valid_chunks
  end

  # Divisão inteligente com base em headings Markdown
  def split_by_markdown_sections(text)
    sections = []
    current_heading = "Introduction"
    current_content = ""

    text.each_line do |line|
      if line.match?(/^#+\s+/) # detect heading markdown (#, ##, ### etc.)
        unless current_content.strip.empty?
          sections << { heading: current_heading, content: current_content.strip }
        end

        current_heading = line.strip
        current_content = ""
      else
        current_content << line
      end
    end

    sections << { heading: current_heading, content: current_content.strip } unless current_content.strip.empty?
    sections
  end

  # Tenta identificar seções por títulos, quebras de linha duplas, etc
  def split_by_sections(text)
    # Remove quebras de linha excessivas e normaliza
    normalized_text = text.gsub(/\n{3,}/, "\n\n").strip

    # Tenta dividir por quebras duplas (mudança de parágrafo/seção)
    potential_sections = normalized_text.split(/\n\n+/)

    # Se as "seções" ficaram muito pequenas, agrupa algumas juntas
    sections = []
    current_section = ""

    potential_sections.each do |part|
      if current_section.length + part.length <= DEFAULT_CHUNK_SIZE
        current_section += (current_section.empty? ? "" : "\n\n") + part
      else
        sections << current_section unless current_section.strip.empty?
        current_section = part
      end
    end

    sections << current_section unless current_section.strip.empty?
    sections
  end

  # Para seções muito grandes, quebra respeitando parágrafos
  def split_large_section(section)
    chunks = []
    paragraphs = section.split(/\n+/)
    current_chunk = ""

    paragraphs.each do |paragraph|
      # Se adicionar este parágrafo não ultrapassar o limite
      if current_chunk.length + paragraph.length <= DEFAULT_CHUNK_SIZE
        current_chunk += (current_chunk.empty? ? "" : "\n") + paragraph
      else
        # Salva o chunk atual (se não estiver vazio)
        chunks << current_chunk unless current_chunk.strip.empty?

        # Se o parágrafo sozinho já é muito grande, quebra ele também
        if paragraph.length > DEFAULT_CHUNK_SIZE
          chunks.concat(split_by_sentences(paragraph))
          current_chunk = ""
        else
          # Inicia novo chunk com este parágrafo
          current_chunk = paragraph
        end
      end
    end

    chunks << current_chunk unless current_chunk.strip.empty?
    chunks
  end

  # Quebra por sentenças quando um parágrafo é muito grande
  def split_by_sentences(text)
    sentences = text.split(/[.!?]+\s+/)
    chunks = []
    current_chunk = ""

    sentences.each do |sentence|
      test_chunk = current_chunk.empty? ? sentence : "#{current_chunk}. #{sentence}"

      if test_chunk.length <= DEFAULT_CHUNK_SIZE
        current_chunk = test_chunk
      else
        chunks << current_chunk unless current_chunk.strip.empty?
        current_chunk = sentence
      end
    end

    chunks << current_chunk unless current_chunk.strip.empty?
    chunks
  end

  # Estratégia de fallback: chunking por tamanho fixo com overlap
  def fallback_chunking(text)
    chunks = []
    start = 0

    while start < text.length
      # Define o fim do chunk
      chunk_end = [ start + DEFAULT_CHUNK_SIZE, text.length ].min

      # Tenta quebrar em uma palavra completa
      if chunk_end < text.length
        # Procura o último espaço antes do limite
        while chunk_end > start && text[chunk_end] != " "
          chunk_end -= 1
        end

        # Se não achou espaço, usa o limite mesmo
        chunk_end = start + DEFAULT_CHUNK_SIZE if chunk_end == start
      end

      chunk = text[start...chunk_end].strip
      chunks << chunk unless chunk.empty?

      # Próximo chunk começa um pouco antes (overlap)
      start = chunk_end - OVERLAP_SIZE
      start = chunk_end if start <= 0
    end

    chunks
  end

  # Ajusta generate_embeddings_batch para salvar heading
  def generate_embeddings_batch(chunks, document_id, base_metadata)
    embeddings_data = []

    chunks.each_with_index do |chunk, index|
      Rails.logger.debug "Gerando embedding para chunk #{index} (#{chunk[:heading]})"
      embedding = get_embedding(chunk[:text])

      embeddings_data << {
        id: "#{document_id}_chunk_#{index}",
        values: embedding,
        metadata: base_metadata.merge({
          text: chunk[:text],
          heading: chunk[:heading], # 👉 heading preservado
          chunk_index: index,
          document_id: document_id,
          chunk_size: chunk[:text].length
        })
      }
    end

    embeddings_data
  end

  # Chama a API da OpenAI para gerar embedding de um texto
  def get_embedding(text)
    uri = URI("https://api.openai.com/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@openai_api_key}"
    request["Content-Type"] = "application/json"

    request.body = {
      input: text,
      model: "text-embedding-3-small"  # Modelo mais barato e eficiente
    }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    if response.code == "200"
      result["data"][0]["embedding"]
    else
      error_msg = result.dig("error", "message") || response.body
      raise "Erro na OpenAI: #{error_msg}"
    end
  end

  # Faz upload dos embeddings para o Pinecone
  def upload_to_pinecone(embeddings_data)
    uri = URI("#{@pinecone_index_url}/vectors/upsert")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Api-Key"] = @pinecone_api_key
    request["Content-Type"] = "application/json"

    # Pinecone aceita até 100 vetores por request, então fazemos em lotes
    embeddings_data.each_slice(100) do |batch|
      Rails.logger.debug "Enviando lote de #{batch.length} embeddings para Pinecone"

      request.body = { vectors: batch }.to_json

      response = http.request(request)

      unless response.code == "200"
        error_details = JSON.parse(response.body) rescue response.body
        raise "Erro no Pinecone: #{error_details}"
      end

      Rails.logger.debug "Lote enviado com sucesso"
    end
  end
end
