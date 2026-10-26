# Right of access (GDPR art. 15): the account, every conversation, memory and credit movement.
class AccountExport
  def initialize(user) = @user = user

  def to_json(*)
    JSON.pretty_generate(
      account: @user.slice(:email_address, :display_name, :created_at, :registered_at, :credit_balance),
      conversations: @user.conversations.includes(:character, :messages, :memories).map { |c|
        { character: c.character.name, summary: c.summary,
          memories: c.memories.map { _1.slice(:fact, :created_at) },
          messages: c.messages.map { _1.slice(:role, :content, :status, :created_at) } }
      },
      credits: @user.credit_entries.order(:id).map { _1.slice(:amount, :kind, :created_at) }
    )
  end
end
