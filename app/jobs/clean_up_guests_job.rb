# Guests who never signed up are deleted after 30 days of silence, with their conversations (privacy policy).
class CleanUpGuestsJob < ApplicationJob
  queue_as :default

  def perform(older_than: 30.days)
    User.where(registered_at: nil).where(updated_at: ...older_than.ago)
      .where.not(id: Conversation.where(last_message_at: older_than.ago..).select(:user_id))
      .find_each(&:destroy!)
  end
end
