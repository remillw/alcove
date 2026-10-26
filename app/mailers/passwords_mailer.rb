class PasswordsMailer < ApplicationMailer
  def reset(user)
    @url = edit_password_url(user.password_reset_token)
    @minutes = (User::RESET_TTL / 1.minute).to_i
    mail_in_locale user, subject: I18n.t("passwords_mailer.reset.subject", locale: user.locale)
  end
end
