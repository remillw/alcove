class CreateCreditEntries < ActiveRecord::Migration[8.1]
  def change
    # append-only ledger: users.credit_balance is a cache of SUM(amount), updated in the same transaction
    create_table :credit_entries do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.references :message, foreign_key: { on_delete: :nullify }
      t.integer :amount, null: false
      t.string :kind, null: false                     # grant | reserve | release | purchase | adjustment
      t.string :idempotency_key, null: false
      t.jsonb :metadata, null: false, default: {}

      t.datetime :created_at, null: false
    end
    add_index :credit_entries, :idempotency_key, unique: true
    add_index :credit_entries, [ :user_id, :id ]
  end
end
