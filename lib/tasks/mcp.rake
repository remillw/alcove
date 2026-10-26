namespace :mcp do
  desc "Issue a read-only MCP token for an agent: bin/rails 'mcp:token[hermes]' (printed once)"
  task :token, [ :name ] => :environment do |_, args|
    puts McpToken.issue!(args[:name].presence || "agent")
  end

  desc "Revoke every MCP token with this name"
  task :revoke, [ :name ] => :environment do |_, args|
    puts McpToken.where(name: args[:name], revoked_at: nil).update_all(revoked_at: Time.current)
  end
end
