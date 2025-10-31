require "net/http"
require "json"

class Pinecone::Searcher
  def initialize
    @pinecone_api_key   = Settings.reload!.apis.pinecone.api_key
    @pinecone_index_url = Settings.reload!.apis.pinecone.index_name
    @openai_api_key     = Settings.reload!.apis.openai.access_token
  end

  def search(query, top_k: 5, filter: {})
    embedding = get_embedding(query)
    results   = query_pinecone(embedding, top_k: top_k, filter: filter)
    enrich_with_text(results)
  end

  private

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

  def query_pinecone(vector, top_k:, filter:)
    uri = URI("#{@pinecone_index_url}/query")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    req = Net::HTTP::Post.new(uri)
    req["Api-Key"] = @pinecone_api_key
    req["Content-Type"] = "application/json"

    params = { vector: vector, topK: top_k, includeMetadata: true }
    params[:filter] = filter if filter.present?

    req.body = params.to_json
    res = http.request(req)
    raise "Pinecone: #{res.body}" unless res.code == "200"
    JSON.parse(res.body)
  end

  def enrich_with_text(results)
    matches = results["matches"] || []
    hashes  = matches.map { |m| m.dig("metadata", "text_hash") }.compact
    texts   = PineconeChunk.where(text_hash: hashes).pluck(:text_hash, :text).to_h

    matches.map do |m|
      hash = m.dig("metadata", "text_hash")
      {
        id: m["id"],
        score: m["score"],
        heading: m.dig("metadata", "heading"),
        text: texts[hash],
        metadata: m["metadata"]
      }
    end
  end
end
