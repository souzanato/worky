class CreateActions < ActiveRecord::Migration[8.0]
  def change
    create_table :actions do |t|
      t.string :title
      t.text :description
      t.belongs_to :step, null: false, foreign_key: true

      t.timestamps
    end
  end
end
