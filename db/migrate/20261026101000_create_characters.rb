class CreateCharacters < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector"

    create_table :characters do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :role, null: false        # "Neighbourhood librarian"
      t.string :tagline, null: false
      t.text :persona, null: false       # personality, voice, backstory: the character's part of the system prompt
      t.text :boundaries, null: false
      t.text :greeting, null: false      # first line, shown without any API call
      t.jsonb :sample_lines, null: false, default: []
      t.string :traits, array: true, null: false, default: []
      t.string :model, null: false
      t.integer :position, null: false, default: 0
      t.boolean :published, null: false, default: false

      t.timestamps
    end
    add_index :characters, :slug, unique: true
    add_index :characters, [ :published, :position ]
  end
end
