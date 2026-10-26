class AddPromptVersionToUsageEvents < ActiveRecord::Migration[8.1]
  def change
    # which version of the prompts produced this reply: compare versions on real traffic, roll back with evidence
    add_column :usage_events, :prompt_version, :string
    add_index :usage_events, [ :prompt_version, :created_at ]
  end
end
