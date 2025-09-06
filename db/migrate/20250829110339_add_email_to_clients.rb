class AddEmailToClients < ActiveRecord::Migration[8.0]
  def change
    add_column :clients, :email, :string
  end
end
