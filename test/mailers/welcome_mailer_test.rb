require "test_helper"

class WelcomeMailerTest < ActionMailer::TestCase
  test "links to the latest conversation, in the user's language" do
    user = users(:member).tap { _1.locale = "fr" }
    conversation = user.conversations.first || flunk("fixture member needs a conversation")
    mail = WelcomeMailer.welcome(user)
    assert_equal "Bienvenue sur Alcove", mail.subject
    assert_match "Bienvenue sur Alcove, Sam.", mail.text_part.body.to_s
    assert_match %r{/conversations/#{conversation.id}}, mail.text_part.body.to_s
  end

  test "links to the home page when there is no conversation yet" do
    user = User.create!(email_address: "new@example.com", password: "password12", registered_at: Time.current, locale: "en")
    mail = WelcomeMailer.welcome(user)
    assert_match "Welcome to Alcove.", mail.text_part.body.to_s
    assert_match "http://example.com/", mail.text_part.body.to_s
  end
end
