class AddActiveToAiCollectConfigs < ActiveRecord::Migration[8.0]
  def change
    add_column :ai_collect_configs, :active, :boolean
  end
end
