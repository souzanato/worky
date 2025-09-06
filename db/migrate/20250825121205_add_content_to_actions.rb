class AddContentToActions < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :content, :text
  end
end
