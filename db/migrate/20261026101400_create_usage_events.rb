class CreateUsageEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :usage_events do |t|
      t.references :user, foreign_key: { on_delete: :nullify }, index: false
      t.references :message, foreign_key: { on_delete: :nullify }
      t.references :character, foreign_key: true, index: false
      t.string :kind, null: false                     # reply | summary
      t.string :model, null: false
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_tokens, null: false, default: 0
      t.integer :cache_write_tokens, null: false, default: 0
      t.bigint :cost_micros, null: false, default: 0
      t.integer :latency_ms
      t.integer :first_token_ms
      t.string :outcome, null: false                  # completed | failed | cancelled

      t.datetime :created_at, null: false
    end
    add_index :usage_events, :created_at
    add_index :usage_events, [ :user_id, :created_at ]
    add_index :usage_events, [ :character_id, :created_at ]
  end
end
