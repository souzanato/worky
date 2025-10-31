# db/migrate/20251031180000_create_pinecone_chunks.rb
class CreatePineconeChunks < ActiveRecord::Migration[7.0]
  def change
    create_table :pinecone_chunks do |t|
      t.string  :document_id, null: false
      t.integer :chunk_index, null: false
      t.string  :text_hash,   null: false
      t.text    :text,        null: false
      t.string  :heading
      t.integer :chunk_size
      t.timestamps
    end

    add_index :pinecone_chunks, :text_hash, unique: true
    add_index :pinecone_chunks, [ :document_id, :chunk_index ], unique: true
  end
end
