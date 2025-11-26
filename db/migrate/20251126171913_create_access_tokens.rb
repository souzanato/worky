class CreateAccessTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :access_tokens do |t|
      t.string :client
      t.string :token
      t.boolean :active

      t.timestamps
    end
  end
end
