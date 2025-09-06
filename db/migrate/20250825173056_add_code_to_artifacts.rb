class AddCodeToArtifacts < ActiveRecord::Migration[8.0]
  def change
    add_column :artifacts, :code, :string
  end
end
