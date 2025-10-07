class AddCustomAttributesToAiActions < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_actions, :custom_attributes, :jsonb, default: {}, null: false
    add_index  :ai_actions, :custom_attributes, using: :gin
  end
end
