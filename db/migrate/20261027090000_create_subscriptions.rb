class CreateSubscriptions < ActiveRecord::Migration[8.1]
  def change
    # one row per subscription at the provider; the provider is the source of truth, this is our mirror of its state
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.string :provider, null: false
      t.string :external_id, null: false
      t.string :product_key, null: false
      t.string :status, null: false, default: "active"   # active | past_due | canceled
      t.datetime :current_period_start
      t.datetime :current_period_end
      t.datetime :canceled_at

      t.timestamps
    end
    add_index :subscriptions, [ :provider, :external_id ], unique: true
  end
end
