require "test_helper"

class PasswordsMailerTest < ActionMailer::TestCase
  test "english mail for an english user" do
    user = users(:member).tap { _1.locale = "en" }
    mail = PasswordsMailer.reset(user)
    assert_equal [ "member@example.com" ], mail.to
    assert_equal "Reset your Alcove password", mail.subject
    assert_match "Choose a new password", mail.html_part.body.to_s
    assert_match %r{/passwords/.+/edit}, mail.text_part.body.to_s
  end

  test "french mail for a french user, whatever the current locale" do
    user = users(:member).tap { _1.locale = "fr" }
    mail = I18n.with_locale(:en) { PasswordsMailer.reset(user) }
    assert_equal "Réinitialisez votre mot de passe Alcove", mail.subject
    assert_match "Choisir un nouveau mot de passe", mail.html_part.body.to_s
    assert_match "30 minutes", mail.text_part.body.to_s
  end
end
