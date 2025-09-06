class RemoveHasPromptGeneratorFromAiActions < ActiveRecord::Migration[8.0]
  def change
    remove_column :ai_actions, :has_prompt_generator, :boolean
  end
end
