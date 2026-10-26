class CreatePayments < ActiveRecord::Migration[8.1]
  def change
    # one attempt to buy something. Created pending BEFORE we talk to the provider, with amount and credits copied from
    # the product catalogue (never from the browser). `token` is our idempotency key and the reference the provider
    # echoes back in its webhooks; `external_id` is the provider's own payment reference, known once it has paid.
    # `checkout_ref` is its hosted checkout session.
    create_table :payments do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :subscription, foreign_key: { on_delete: :nullify }
      t.string :provider, null: false
      t.string :token, null: false
      t.string :external_id
      t.string :checkout_ref                              # the provider's checkout session, kept to ask it later (reconciliation)
      t.string :product_key, null: false
      t.string :status, null: false, default: "pending"   # pending | paid | failed | expired | refunded
      t.integer :amount_cents, null: false
      t.string :currency, null: false, default: "EUR"
      t.integer :credits, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :paid_at

      t.timestamps
    end
    add_index :payments, :token, unique: true
    add_index :payments, [ :provider, :external_id ], unique: true, where: "external_id IS NOT NULL"
    add_index :payments, :created_at, where: "status = 'pending'", name: "index_payments_pending_on_created_at"
  end
end
