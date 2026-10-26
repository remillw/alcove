class ApplicationMailer < ActionMailer::Base
  default from: -> { ENV.fetch("MAIL_FROM", "Alcove <hello@victoire-digital.fr>") }
  layout "mailer"

  private

  # Mails are rendered in the recipient's language (users.locale), whatever the job's own locale is.
  def mail_in_locale(user, **)
    I18n.with_locale(user.locale) { mail(to: user.email_address, **) }
  end
end
