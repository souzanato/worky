require "net/http"
require "json"
require "zlib"
require "base64"

class Pinecone::Searcher
  def initialize
    @pinecone_api_key   = Settings.reload!.apis.pinecone.api_key
    @pinecone_index_url = Settings.reload!.apis.pinecone.index_name
    @openai_api_key     = Settings.reload!.apis.openai.access_token
  end

  def search(query, top_k: 5, include_metadata: true, filter: {})
    # 1. Gerar embedding da query
    query_embedding = get_embedding(query)

    # 2. Buscar no Pinecone
    search_results = query_pinecone(
      query_embedding,
      top_k: top_k,
      include_metadata: include_metadata,
      filter: filter
    )

    # 3. Processar resultados
    process_search_results(search_results)
  end

  # Busca por artifacts específicos
  def search_artifacts(query, artifact_ids: [], top_k: 5)
    filter = {}
    filter[:artifact_id] = { "$in": artifact_ids } unless artifact_ids.empty?
    search(query, top_k: top_k, filter: filter)
  end

  # Busca com score mínimo
  def search_with_threshold(query, min_score: 0.7, top_k: 10)
    results = search(query, top_k: top_k)
    results.select { |result| result[:score] >= min_score }
  end

  private

  def get_embedding(text)
    uri = URI("https://api.openai.com/v1/embeddings")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@openai_api_key}"
    request["Content-Type"] = "application/json"

    request.body = {
      input: text,
      model: "text-embedding-3-small"
    }.to_json

    response = http.request(request)
    result = JSON.parse(response.body)

    if response.code == "200"
      result["data"][0]["embedding"]
    else
      raise "Erro na OpenAI: #{result.dig('error', 'message') || response.body}"
    end
  end

  def query_pinecone(query_embedding, top_k:, include_metadata:, filter:)
    uri = URI("#{@pinecone_index_url}/query")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri)
    request["Api-Key"] = @pinecone_api_key
    request["Content-Type"] = "application/json"

    query_params = {
      vector: query_embedding,
      topK: top_k,
      includeMetadata: include_metadata
    }
    query_params[:filter] = filter unless filter.empty?

    request.body = query_params.to_json

    response = http.request(request)

    if response.code == "200"
      JSON.parse(response.body)
    else
      error_details = JSON.parse(response.body) rescue response.body
      raise "Erro no Pinecone: #{error_details}"
    end
  end

  def process_search_results(results)
    matches = results["matches"] || []

    matches.map do |match|
      metadata = match["metadata"] || {}

      # Suporte à compressão (text_gz) com fallback para metadata["text"]
      text =
        if metadata["text_gz"]
          begin
            Zlib::Inflate.inflate(Base64.decode64(metadata["text_gz"]))
          rescue
            "[Erro ao descomprimir texto]"
          end
        else
          metadata["text"]
        end

      {
        id: match["id"],
        score: match["score"],
        metadata: metadata,
        text: text,
        artifact_id: metadata["artifact_id"],
        chunk_index: metadata["chunk_index"]
      }
    end
  end
end
