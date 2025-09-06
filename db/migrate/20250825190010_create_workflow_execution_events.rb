class CreateWorkflowExecutionEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_execution_events do |t|
      t.belongs_to :action, null: false, foreign_key: true
      t.jsonb :input_data
      t.jsonb :output_data
      t.integer :status, null: false, default: 0
      t.belongs_to :workflow_execution, null: false, foreign_key: true

      t.timestamps
    end

    add_index :workflow_execution_events, :input_data, using: :gin, name: "index_wfe_on_input"
    add_index :workflow_execution_events, :output_data, using: :gin, name: "index_wfe_on_output"
  end
end
