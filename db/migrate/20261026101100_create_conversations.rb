class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversations do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :character, null: false, foreign_key: true
      t.text :summary
      t.bigint :summarized_until_message_id
      t.datetime :last_message_at

      t.timestamps
    end
    # one ongoing relationship per character, like a companion
    add_index :conversations, [ :user_id, :character_id ], unique: true
    add_index :conversations, [ :user_id, :last_message_at ]
  end
end
