class CreateWorkflowExecutions < ActiveRecord::Migration[8.0]
  def change
    create_table :workflow_executions do |t|
      t.belongs_to :client, null: false, foreign_key: true
      t.belongs_to :user, null: false, foreign_key: true
      t.belongs_to :workflow, null: false, foreign_key: true
      t.belongs_to :current_action, foreign_key: { to_table: :actions }

      t.datetime :started_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :finished_at

      # status geral da execução
      t.integer :status, null: false, default: 0

      t.timestamps
    end

    # index pra consultas rápidas
    add_index :workflow_executions, :status
    add_index :workflow_executions, :started_at
  end
end
