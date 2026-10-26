class CreateMemories < ActiveRecord::Migration[8.1]
  def change
    # what a character remembers about a user: visible to the user, and they can make it forget
    create_table :memories do |t|
      t.references :conversation, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.text :fact, null: false
      t.integer :importance, null: false, default: 1
      t.references :source_message, foreign_key: { to_table: :messages, on_delete: :nullify }
      t.vector :embedding, limit: 1024                # semantic recall comes later: v1 uses the most important facts

      t.timestamps
    end
    add_index :memories, [ :conversation_id, :importance, :id ]
  end
end
