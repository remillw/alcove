class CreateReports < ActiveRecord::Migration[8.1]
  def change
    # a user flags a reply; safety events are logged here too (kind: distress, blocked_input, blocked_output)
    create_table :reports do |t|
      t.references :message, foreign_key: { on_delete: :cascade }
      t.references :user, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.text :note
      t.datetime :resolved_at

      t.datetime :created_at, null: false
    end
    add_index :reports, [ :resolved_at, :created_at ]
  end
end
