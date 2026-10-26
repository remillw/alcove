require "test_helper"

class LocaleTest < ActionDispatch::IntegrationTest
  test "French browsers get French, English otherwise, and the switch is remembered" do
    get root_path, headers: { "Accept-Language" => "fr-FR,fr;q=0.9" }
    assert_select "html[lang=fr]"
    assert_match "souvient", response.body

    get root_path, headers: { "Accept-Language" => "en-GB" }
    assert_select "html[lang=en]"

    get root_path(locale: "fr"), headers: { "Accept-Language" => "en-GB" }
    get character_path("june"), headers: { "Accept-Language" => "en-GB" }
    assert_select "html[lang=fr]"
  end

  test "a French speaker in crisis gets French helplines" do
    user = users(:member)
    user.update!(locale: "fr")
    reply = Turn.take!(conversation: conversations(:member_june), content: "I want to die", nonce: SecureRandom.uuid).reply
    assert_match "3114", reply.content
    assert_match "112", reply.content
  end
end
