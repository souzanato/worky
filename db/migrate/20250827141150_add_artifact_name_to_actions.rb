class AddArtifactNameToActions < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :artifact_name, :string
  end
end
