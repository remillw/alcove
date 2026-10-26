class CreateMcpTokens < ActiveRecord::Migration[8.1]
  def change
    # agents reading Alcove's numbers (Hermes): one token per agent, stored as a SHA-256 digest, revocable
    create_table :mcp_tokens do |t|
      t.string :name, null: false
      t.string :digest, null: false
      t.datetime :last_used_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :mcp_tokens, :digest, unique: true
  end
end
