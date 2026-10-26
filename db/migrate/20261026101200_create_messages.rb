class CreateMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :messages do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :role, null: false                     # user | assistant
      t.text :content, null: false, default: ""
      t.string :status, null: false, default: "completed" # pending | streaming | completed | failed | cancelled | blocked
      t.string :model
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.bigint :cost_micros                           # real cost, millionths of a dollar: never a float
      t.string :error_code
      t.datetime :cancel_requested_at
      t.uuid :client_nonce                            # a double click or a retried request posts once

      t.timestamps
    end
    add_index :messages, [ :conversation_id, :id ]
    add_index :messages, [ :conversation_id, :client_nonce ], unique: true, where: "client_nonce IS NOT NULL"
    # one reply being written per conversation, guaranteed by the database
    add_index :messages, :conversation_id, unique: true, name: "one_active_reply_per_conversation",
      where: "role = 'assistant' AND status IN ('pending', 'streaming')"
    add_check_constraint :messages, "role IN ('user', 'assistant')", name: "message_role"
    add_check_constraint :messages,
      "status IN ('pending', 'streaming', 'completed', 'failed', 'cancelled', 'blocked')", name: "message_status"
  end
end
