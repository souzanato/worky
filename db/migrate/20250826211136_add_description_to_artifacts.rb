class AddDescriptionToArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :artifacts, :description, :text
  end
end
