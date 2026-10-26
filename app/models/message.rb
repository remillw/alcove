class Message < ApplicationRecord
  MAX_LENGTH = 1_000
  ACTIVE = %w[pending streaming].freeze

  belongs_to :conversation, touch: :last_message_at
  has_many :reports, dependent: :delete_all

  validates :role, inclusion: { in: %w[user assistant] }
  validates :content, length: { maximum: MAX_LENGTH }, presence: true, if: -> { role == "user" }

  delegate :user, :character, to: :conversation

  def assistant? = role == "assistant"
  def active? = ACTIVE.include?(status)
  def cancelled? = status == "cancelled"
  def failed? = status == "failed"
end
