module SearchableInPinecone
  extend ActiveSupport::Concern

  def search_in_pinecone(query, top_k: 5, min_score: nil)
    filter = {
      resource_type: { "$eq": self.class.name },
      resource_id:   { "$eq": id }
    }

    searcher = Pinecone::Searcher.new
    results = searcher.search(query, top_k: top_k, filter: filter)

    if min_score
      results.select { |r| r[:score] >= min_score }
    else
      results
    end
  end
end
