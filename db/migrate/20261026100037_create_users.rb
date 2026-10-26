class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      # nil for guests: a visitor chats before signing up, and keeps everything when they do
      t.string :email_address
      t.string :password_digest
      t.string :display_name
      t.integer :credit_balance, null: false, default: 0
      t.datetime :adult_confirmed_at
      t.datetime :registered_at

      t.timestamps
    end
    add_index :users, :email_address, unique: true, where: "email_address IS NOT NULL"
    add_check_constraint :users, "credit_balance >= 0", name: "credit_balance_not_negative"
  end
end
