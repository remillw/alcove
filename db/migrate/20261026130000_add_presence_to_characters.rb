class AddPresenceToCharacters < ActiveRecord::Migration[8.1]
  def change
    change_table :characters, bulk: true do |t|
      t.string :accent, null: false, default: "#E2A24B"
      t.string :keepsake, null: false, default: "none"      # what the character keeps for you: reading_pile, case_file...
      t.jsonb :statuses, null: false, default: {}           # what they're doing, by time of day
      t.jsonb :starters, null: false, default: []           # reply suggestions for the very first message
      t.jsonb :returns, null: false, default: {}            # hand-written openings when you come back
      t.jsonb :showcase, null: false, default: []           # a short real-sounding exchange for the home page
    end
    add_column :conversations, :suggestions, :jsonb, null: false, default: []
    add_column :messages, :part_of_id, :bigint            # a reply sent as 2 or 3 short messages points to the first one

    create_table :keepsake_items do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :key, null: false       # stable handle chosen by the model: "piranesi", "bram-oake"
      t.string :status
      t.string :title, null: false
      t.text :detail
      t.text :note
      t.references :source_message, foreign_key: { to_table: :messages, on_delete: :nullify }
      t.timestamps
    end
    add_index :keepsake_items, [ :conversation_id, :key ], unique: true
  end
end
