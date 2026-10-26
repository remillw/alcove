class CreateWebhookEvents < ActiveRecord::Migration[8.1]
  def change
    # every verified webhook, kept as received. The unique (provider, event_id) is what makes a replayed event a no-op.
    create_table :webhook_events do |t|
      t.string :provider, null: false
      t.string :event_id, null: false
      t.string :event_type, null: false
      t.jsonb :payload, null: false, default: {}
      t.datetime :processed_at

      t.datetime :created_at, null: false
    end
    add_index :webhook_events, [ :provider, :event_id ], unique: true
  end
end
