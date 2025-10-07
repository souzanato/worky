class AddAllowPromptingToActions < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :allow_prompting, :boolean
  end
end
