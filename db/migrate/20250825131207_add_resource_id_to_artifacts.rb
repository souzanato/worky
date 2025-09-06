class AddResourceIdToArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :artifacts, :resource_id, :integer
  end
end
