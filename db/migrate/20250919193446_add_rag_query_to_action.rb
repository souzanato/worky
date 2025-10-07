class AddRagQueryToAction < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :rag_query, :jsonb, default: {}, null: false
    add_index :actions, :rag_query, using: :gin
  end
end
