require "test_helper"

class FirstConversationTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "a visitor confirms their age, talks, runs out, signs up and keeps the conversation" do
    get character_path("june")
    assert_response :success

    post conversation_character_path("june")
    assert_redirected_to character_path("june") # age not confirmed

    post conversation_character_path("june"), params: { adult: "1" }
    conversation = Conversation.last
    assert_redirected_to conversation_path(conversation)
    guest = conversation.user
    assert guest.guest?
    assert_equal User::GUEST_CREDITS, guest.credit_balance

    perform_enqueued_jobs do
      post conversation_messages_path(conversation), params: { content: "Hi June", nonce: SecureRandom.uuid }, as: :turbo_stream
    end
    assert_response :success
    assert_equal "completed", conversation.messages.last.status

    guest.update_columns(credit_balance: 0)
    post conversation_messages_path(conversation), params: { content: "Again", nonce: SecureRandom.uuid }, as: :turbo_stream
    assert_response :payment_required
    assert_match "Create a free account", response.body

    post registration_path, params: { email_address: "new@example.com", password: "a-long-password", adult: "1", terms: "1" }
    assert_redirected_to conversation_path(conversation)
    assert guest.reload.registered?
    assert_equal User::SIGNUP_CREDITS, guest.credit_balance
  end

  test "someone can't read another person's conversation" do
    sign_in_as users(:guest)
    get conversation_path(conversations(:member_june))
    assert_response :not_found
  end

  test "deleting the account erases conversations and memories" do
    sign_in_as users(:member)
    conversations(:member_june).memories.create!(fact: "Has a cat")
    delete account_path
    assert_not User.exists?(users(:member).id)
    assert_equal 0, Memory.count
  end
end
