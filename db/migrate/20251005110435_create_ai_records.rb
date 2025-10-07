class CreateAiRecords < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_records do |t|
      t.string :source_type, null: false
      t.string :ai_action, null: false
      t.string :ai_model
      t.text :content
      t.jsonb :output, default: {}, null: false

      t.timestamps
    end
  end
end
