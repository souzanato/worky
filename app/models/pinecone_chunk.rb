# app/models/pinecone_chunk.rb
class PineconeChunk < ApplicationRecord
  validates :document_id, :chunk_index, :text_hash, :text, presence: true
  validates :text_hash, uniqueness: true

  before_validation :set_text_hash, if: -> { text.present? && text_hash.blank? }

  def set_text_hash
    self.text_hash = Digest::SHA1.hexdigest(text)
  end
end
