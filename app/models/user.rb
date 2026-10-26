class User < ApplicationRecord
  GUEST_CREDITS = 10
  SIGNUP_CREDITS = 30

  has_secure_password validations: false
  has_many :sessions, dependent: :destroy
  has_many :conversations, dependent: :destroy
  has_many :credit_entries, dependent: :delete_all
  has_many :payments, dependent: :delete_all
  has_many :subscriptions, dependent: :delete_all

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }, if: :registered?
  validates :password, length: { minimum: 10 }, allow_nil: true, if: :registered?
  validates :password_digest, presence: true, if: :registered?

  def self.create_guest!
    transaction do
      create!.tap { |user| Credits.post!(user:, amount: GUEST_CREDITS, kind: :grant, key: "guest:#{user.id}") }
    end
  end

  def guest? = registered_at.nil?
  def registered? = registered_at.present?
  def adult? = adult_confirmed_at.present?

  # the guest becomes a member: same row, so conversations and memories stay
  def register!(email_address:, password:, display_name: nil)
    transaction do
      update!(email_address:, password:, display_name: display_name.presence, registered_at: Time.current,
        adult_confirmed_at: adult_confirmed_at || Time.current)
      Credits.post!(user: self, amount: SIGNUP_CREDITS, kind: :grant, key: "signup:#{id}")
    end
  end

  def active_subscription = subscriptions.active.where("current_period_end > ?", Time.current).order(:id).last

  def name_for_characters = display_name.presence
end
