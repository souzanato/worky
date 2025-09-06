class AddResourceTypeToArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :artifacts, :resource_type, :string
  end
end
