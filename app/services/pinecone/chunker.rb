require "net/http"
require "json"
require "uri"
require "zlib"
require "base64"

class Pinecone::Chunker
  # Configurações padrão para o chunking
  DEFAULT_CHUNK_SIZE = 1200      # Tamanho alvo de cada chunk (caracteres)
  MIN_CHUNK_SIZE     = 50        # Tamanho mínimo (flexível)
  OVERLAP_SIZE       = 150       # Sobreposição entre chunks (reserva futura)
  MAX_PAYLOAD_SIZE   = 1_900_000 # ~1.9MB (limite prático da API é 2MB)

  def initialize(min_chunk_size: MIN_CHUNK_SIZE)
    @pinecone_api_key   = Settings.reload!.apis.pinecone.api_key
    @pinecone_index_url = Settings.reload!.apis.pinecone.index_name
    @openai_api_key     = Settings.reload!.apis.openai.access_token
    @min_chunk_size     = min_chunk_size

    raise "PINECONE_API_KEY não configurada"   unless @pinecone_api_key.present?
    raise "PINECONE_INDEX_HOST não configurada" unless @pinecone_index_url.present?
    raise "OPENAI_API_KEY não configurada"     unless @openai_api_key.present?
  end

  # Método principal que recebe o texto e processa tudo
  def process_document(text, document_id:, metadata: {})
    Rails.logger.info "🔄 Iniciando processamento do documento #{document_id}..."
    Rails.logger.info "📝 Texto original: #{text.to_s.length} caracteres"

    if text.blank?
      Rails.logger.warn "⚠️ Texto vazio fornecido"
      return { success: false, error: "Texto vazio", chunks_count: 0, document_id: document_id }
    end

    # 1. Chunking
    chunks = create_chunks(text)
    Rails.logger.info "✅ Criados #{chunks.length} chunks"

    if chunks.empty?
      Rails.logger.warn "⚠️ Nenhum chunk foi criado após processamento"
      return { success: false, error: "Nenhum chunk válido criado", chunks_count: 0, document_id: document_id }
    end

    chunks.each_with_index do |chunk, i|
      Rails.logger.debug "Chunk #{i}: #{chunk[:text].length} chars (#{chunk[:heading]}) - '#{chunk[:text][0..50]}...'"
    end

    # 2. Embeddings
    embeddings_data = generate_embeddings_batch(chunks, document_id, metadata)
    Rails.logger.info "✅ Embeddings gerados para #{embeddings_data.length} chunks"

    # 3. Upload Pinecone
    upload_to_pinecone(embeddings_data)
    Rails.logger.info "✅ Upload para Pinecone concluído"

    {
      success: true,
      chunks_count: chunks.length,
      document_id: document_id
    }
  rescue => e
    Rails.logger.error "❌ Erro no processamento: #{e.class.name} - #{e.message}"
    Rails.logger.error "Backtrace: #{e.backtrace.first(5).join(' | ')}"
    { success: false, error: e.message, chunks_count: 0, document_id: document_id }
  end

  private

  # ---------- Chunking ----------
  def create_chunks(text)
    return [] if text.blank?

    chunks = []
    markdown_sections = split_by_markdown_sections(text)
    Rails.logger.info "Dividido em #{markdown_sections.length} seções Markdown"

    markdown_sections.each do |section|
      heading = section[:heading]
      content = section[:content]

      split_large_section(content).each do |subchunk|
        next if subchunk.strip.length < @min_chunk_size
        chunks << { heading: heading, text: subchunk }
      end
    end

    # fallback relaxado se tudo foi rejeitado
    if chunks.empty?
      Rails.logger.warn "Todos os chunks foram rejeitados. Relaxando filtro"
      markdown_sections.each do |section|
        split_large_section(section[:content]).each do |subchunk|
          chunks << { heading: section[:heading], text: subchunk } if subchunk.strip.length >= 10
        end
      end
    end

    chunks
  end

  def split_by_markdown_sections(text)
    sections = []
    current_heading = "Introduction"
    current_content = ""

    text.each_line do |line|
      if line.match?(/^#+\s+/)
        sections << { heading: current_heading, content: current_content.strip } unless current_content.strip.empty?
        current_heading = line.strip
        current_content = ""
      else
        current_content << line
      end
    end
    sections << { heading: current_heading, content: current_content.strip } unless current_content.strip.empty?
    sections
  end

  def split_large_section(section)
    chunks = []
    paragraphs = section.split(/\n+/)
    current_chunk = ""

    paragraphs.each do |paragraph|
      if current_chunk.length + paragraph.length <= DEFAULT_CHUNK_SIZE
        current_chunk += (current_chunk.empty? ? "" : "\n") + paragraph
      else
        chunks << current_chunk unless current_chunk.strip.empty?
        if paragraph.length > DEFAULT_CHUNK_SIZE
          chunks.concat(split_by_sentences(paragraph))
          current_chunk = ""
        else
          current_chunk = paragraph
        end
      end
    end
    chunks << current_chunk unless current_chunk.strip.empty?
    chunks
  end

  def split_by_sentences(text)
    sentences = text.split(/[.!?]+\s+/)
    chunks, current_chunk = [], ""
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

  # ---------- Embeddings ----------
  def generate_embeddings_batch(chunks, document_id, base_metadata)
    embeddings_data = []
    chunks.each_with_index do |chunk, index|
      Rails.logger.debug "Gerando embedding para chunk #{index} (#{chunk[:heading]})"
      embedding   = get_embedding(chunk[:text])

      # Compressão do texto para reduzir payload (gzip + Base64)
      compressed  = Base64.strict_encode64(Zlib::Deflate.deflate(chunk[:text]))

      embeddings_data << {
        id: "#{document_id}_chunk_#{index}",
        values: embedding,
        metadata: base_metadata.merge({
          text_gz: compressed,         # texto comprimido (fallback: manter 'text' se quiser)
          heading: chunk[:heading],
          chunk_index: index,
          document_id: document_id,
          chunk_size: chunk[:text].length
        })
      }
    end
    embeddings_data
  end

  def get_embedding(text)
    uri = URI("https://api.openai.com/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@openai_api_key}"
    request["Content-Type"] = "application/json"
    request.body = { input: text, model: "text-embedding-3-small" }.to_json
    response = http.request(request)
    result = JSON.parse(response.body)
    if response.code == "200"
      result["data"][0]["embedding"]
    else
      error_msg = result.dig("error", "message") || response.body
      raise "Erro na OpenAI: #{error_msg}"
    end
  end

  # ---------- Upload Pinecone ----------
  def upload_to_pinecone(embeddings_data)
    uri = URI("#{@pinecone_index_url}/vectors/upsert")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri)
    request["Api-Key"] = @pinecone_api_key
    request["Content-Type"] = "application/json"

    batch, size_accum = [], 0

    embeddings_data.each do |vector|
      vector_json = vector.to_json
      if size_accum + vector_json.bytesize > MAX_PAYLOAD_SIZE
        send_batch(http, request, batch) unless batch.empty?
        batch, size_accum = [], 0
      end
      batch << vector
      size_accum += vector_json.bytesize
    end

    send_batch(http, request, batch) unless batch.empty?
  end

  def send_batch(http, request, batch, retries: 3)
    return if batch.empty?

    request.body = { vectors: batch }.to_json
    attempt = 0

    begin
      attempt += 1
      response = http.request(request)
      if response.code == "200"
        Rails.logger.debug "✅ Lote de #{batch.size} embeddings enviado com sucesso (#{request.body.bytesize} bytes)"
      else
        error_details = JSON.parse(response.body) rescue response.body
        raise "Erro no Pinecone: #{error_details}"
      end
    rescue => e
      if attempt < retries
        Rails.logger.warn "⚠️ Falha no envio (tentativa #{attempt}): #{e.message}. Reenviando..."
        sleep(1.5 * attempt)
        retry
      else
        Rails.logger.error "❌ Erro permanente no upload: #{e.message}"
        raise
      end
    end
  end
end
