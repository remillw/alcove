# Open /rails/mailers in development.
class WelcomeMailerPreview < ActionMailer::Preview
  def welcome_en = WelcomeMailer.welcome(user("en"))
  def welcome_fr = WelcomeMailer.welcome(user("fr"))

  private

  def user(locale) = User.registered.first&.tap { |u| u.locale = locale } || User.new(email_address: "you@example.com", locale:, display_name: "Sam")
end
