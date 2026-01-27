class AddBestModelPickerToAiAction < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_actions, :best_model_picker, :boolean
  end
end
