class Conversation < ApplicationRecord
  SUMMARY_EVERY = 16

  belongs_to :user
  belongs_to :character
  has_many :messages, -> { order(:id) }, dependent: :delete_all
  has_many :memories, dependent: :delete_all

  def active_reply = messages.find_by(role: "assistant", status: %w[pending streaming])

  def needs_summary?
    messages.where(status: "completed").where("id > ?", summarized_until_message_id.to_i).count >= SUMMARY_EVERY
  end
end
