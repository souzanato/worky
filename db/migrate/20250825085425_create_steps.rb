class CreateSteps < ActiveRecord::Migration[8.0]
  def change
    create_table :steps do |t|
      t.string :title
      t.text :description
      t.belongs_to :workflow, null: false, foreign_key: true

      t.timestamps
    end
  end
end
