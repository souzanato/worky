class CreateAiActions < ActiveRecord::Migration[8.0]
  def change
    create_table :ai_actions do |t|
      t.string :ai_model
      t.belongs_to :action, null: false, foreign_key: true

      t.timestamps
    end
  end
end
