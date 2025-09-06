class AddOrderToSteps < ActiveRecord::Migration[8.0]
  def change
    add_column :steps, :order, :integer
  end
end
