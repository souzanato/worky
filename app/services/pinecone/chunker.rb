require "net/http"
require "json"
require "uri"
require "digest/sha1"

class Pinecone::Chunker
  DEFAULT_CHUNK_SIZE = 1200
  MIN_CHUNK_SIZE     = 50
  OVERLAP_SIZE       = 150
  MAX_PAYLOAD_SIZE   = 1_900_000
  METADATA_LIMIT     = 40_960

  def initialize
    @pinecone_api_key   = Settings.reload!.apis.pinecone.api_key
    @pinecone_index_url = Settings.reload!.apis.pinecone.index_name
    @openai_api_key     = Settings.reload!.apis.openai.access_token
  end

  def process_document(text, document_id:, metadata: {})
    raise "Texto vazio" if text.blank?

    chunks = create_chunks(text)
    Rails.logger.info "📚 Criados #{chunks.size} chunks para #{document_id}"

    embeddings_data = generate_embeddings(chunks, document_id, metadata)
    upload_to_pinecone(embeddings_data)

    { success: true, chunks_count: chunks.size }
  rescue => e
    Rails.logger.error "❌ Erro: #{e.class} - #{e.message}"
    { success: false, error: e.message }
  end

  private

  # --- chunking simples
  def create_chunks(text)
    paragraphs = text.split(/\n+/)
    chunks, current = [], ""

    paragraphs.each do |p|
      if (current.length + p.length) <= DEFAULT_CHUNK_SIZE
        current += (current.empty? ? "" : "\n") + p
      else
        chunks << current.strip unless current.strip.empty?
        current = p
      end
    end
    chunks << current.strip unless current.strip.empty?
    chunks
  end

  # --- gera embeddings e salva os textos no banco
  def generate_embeddings(chunks, document_id, base_metadata)
    chunks.map.with_index do |chunk_text, i|
      embedding = get_embedding(chunk_text)
      text_hash = Digest::SHA1.hexdigest(chunk_text)

      PineconeChunk.find_or_create_by!(
        document_id: document_id,
        chunk_index: i,
        text_hash: text_hash
      ) do |pc|
        pc.text       = chunk_text
        pc.heading    = base_metadata[:heading]
        pc.chunk_size = chunk_text.length
      end

      # --- 🔧 Ajuste começa aqui ---
      meta = {
        document_id: document_id,
        chunk_index: i,
        text_hash: text_hash,
        heading: base_metadata[:heading]
      }.compact  # remove nils

      # converte todos os valores pra string (garante compatibilidade)
      meta.transform_values!(&:to_s)
      # --- 🔧 Ajuste termina aqui ---

      {
        id: "#{document_id}_chunk_#{i}",
        values: embedding,
        metadata: meta
      }
    end
  end


  # --- embedding OpenAI
  def get_embedding(text)
    uri = URI("https://api.openai.com/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Bearer #{@openai_api_key}"
    req["Content-Type"] = "application/json"
    req.body = { input: text, model: "text-embedding-3-small" }.to_json

    res = http.request(req)
    raise "OpenAI: #{res.body}" unless res.code == "200"
    JSON.parse(res.body).dig("data", 0, "embedding")
  end

  # --- upload Pinecone (com retry)
  def upload_to_pinecone(embeddings_data)
    uri = URI("#{@pinecone_index_url}/vectors/upsert")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Api-Key"] = @pinecone_api_key
    request["Content-Type"] = "application/json"

    batch, size = [], 0
    embeddings_data.each do |vector|
      json = vector.to_json
      if size + json.bytesize > MAX_PAYLOAD_SIZE
        send_batch(http, request, batch)
        batch, size = [], 0
      end
      batch << vector
      size += json.bytesize
    end
    send_batch(http, request, batch) unless batch.empty?
  end

  def send_batch(http, request, batch, retries: 3)
    return if batch.empty?
    attempt = 0

    begin
      attempt += 1
      request.body = { vectors: batch }.to_json
      res = http.request(request)
      if res.code == "200"
        Rails.logger.info "✅ Enviado #{batch.size} vetores (#{request.body.bytesize} bytes)"
      else
        raise "Pinecone: #{res.body}"
      end
    rescue => e
      if attempt < retries
        sleep(1.5 * attempt)
        retry
      else
        raise e
      end
    end
  end
end
