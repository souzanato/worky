class CreateAiCollectConfigs < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_collect_configs do |t|
      t.string :title
      t.string :code
      t.text :description
      t.text :prompt
      t.string :ai_model
      t.belongs_to :workflow, null: false, foreign_key: true

      t.timestamps
    end
  end
end
