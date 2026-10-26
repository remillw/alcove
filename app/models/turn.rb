# A user speaks: their message is saved, one credit is reserved and the character's reply is queued, all or
# nothing. A crisis or a forbidden request gets a written answer at once, without a model call or a credit.
class Turn
  Result = Data.define(:message, :reply, :error)

  def self.take!(conversation:, content:, nonce:)
    new(conversation, content.to_s.strip, nonce).take!
  end

  def initialize(conversation, content, nonce)
    @conversation, @content, @nonce = conversation, content, nonce
    @user = conversation.user
  end

  def take!
    if (existing = @conversation.messages.find_by(client_nonce: @nonce))
      return Result.new(existing, @conversation.messages.where("id > ?", existing.id).first, nil)
    end
    return Result.new(nil, nil, :busy) if @conversation.active_reply

    case Safety.check(@content)
    when :distress then answer_directly(Safety::DISTRESS_REPLY, "distress")
    when :forbidden then answer_directly(Safety::REFUSAL_REPLY, "blocked_input")
    else queue_reply
    end
  rescue Credits::InsufficientBalance
    Result.new(nil, nil, :no_credits)
  rescue ActiveRecord::RecordNotUnique
    Result.new(nil, nil, :busy) # a reply started in another tab a moment ago
  rescue ActiveRecord::RecordInvalid => e
    Result.new(e.record, nil, :invalid)
  end

  private

  def queue_reply
    message = reply = nil
    Message.transaction do
      message = @conversation.messages.create!(role: "user", content: @content, client_nonce: @nonce)
      reply = @conversation.messages.create!(role: "assistant", status: "pending", model: @conversation.character.model)
      Credits.post!(user: @user, amount: -1, kind: :reserve, key: "reply:#{reply.id}:reserve", message: reply)
    end
    GenerateReplyJob.perform_later(reply.id)
    Result.new(message, reply, nil)
  end

  def answer_directly(text, kind)
    Message.transaction do
      message = @conversation.messages.create!(role: "user", content: @content, client_nonce: @nonce)
      reply = @conversation.messages.create!(role: "assistant", status: "blocked", content: text)
      Report.create!(message:, user: @user, kind:)
      Result.new(message, reply, nil)
    end
  end
end
