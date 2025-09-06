class AddAiActionToActions < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :has_ai_action, :boolean
  end
end
