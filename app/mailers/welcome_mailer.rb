class WelcomeMailer < ApplicationMailer
  def welcome(user)
    last = user.conversations.order(last_message_at: :desc).first
    @url = last ? conversation_url(last) : root_url
    @continuing = last.present?
    @name = user.display_name
    mail_in_locale user, subject: I18n.t("welcome_mailer.welcome.subject", locale: user.locale)
  end
end
