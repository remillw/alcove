class AddLocales < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :locale, :string, null: false, default: "en"
    # French texts of a character (role, tagline, greeting, starters, statuses...): the persona itself stays in
    # English, the model answers in the user's language
    add_column :characters, :translations, :jsonb, null: false, default: {}
  end
end
