class AddHasPromptGeneratorToAiActions < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_actions, :has_prompt_generator, :boolean
  end
end
