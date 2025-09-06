class AddOrderToActions < ActiveRecord::Migration[8.0]
  def change
    add_column :actions, :order, :integer
  end
end
