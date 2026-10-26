# Open /rails/mailers in development.
class PasswordsMailerPreview < ActionMailer::Preview
  def reset_en = PasswordsMailer.reset(user("en"))
  def reset_fr = PasswordsMailer.reset(user("fr"))

  private

  def user(locale) = User.registered.first&.tap { |u| u.locale = locale } || User.new(email_address: "you@example.com", locale:, registered_at: Time.current, password: "password12")
end
