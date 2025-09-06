class AddHasPromptGeneratorToActions < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :has_prompt_generator, :boolean
  end
end
