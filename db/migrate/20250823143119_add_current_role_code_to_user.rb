class AddCurrentRoleCodeToUser < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :current_role_code, :string
  end
end
