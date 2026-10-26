class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    # notifications for Hermes, signed here and relayed by the host (Hermes only listens on the server's loopback)
    create_table :outbox_events do |t|
      t.string :event_type, null: false
      t.text :payload, null: false
      t.datetime :created_at, null: false
    end
  end
end
