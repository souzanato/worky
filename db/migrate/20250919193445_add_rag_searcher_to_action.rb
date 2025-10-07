class AddRagSearcherToAction < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :rag_searcher, :jsonb, default: {}, null: false
    add_index :actions, :rag_searcher, using: :gin
  end
end
