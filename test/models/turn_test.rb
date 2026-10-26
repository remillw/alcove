require "test_helper"

class TurnTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup { @conversation = conversations(:member_june) }

  test "a message reserves one credit and queues the reply" do
    result = nil
    assert_enqueued_with(job: GenerateReplyJob) do
      result = Turn.take!(conversation: @conversation, content: "Hello June", nonce: SecureRandom.uuid)
    end
    assert_nil result.error
    assert_equal "pending", result.reply.status
    assert_equal 4, users(:member).reload.credit_balance
  end

  test "the same nonce posted twice creates one message" do
    nonce = SecureRandom.uuid
    first = Turn.take!(conversation: @conversation, content: "Hello", nonce:)
    second = Turn.take!(conversation: @conversation, content: "Hello", nonce:)
    assert_equal first.message, second.message
    assert_equal 4, users(:member).reload.credit_balance
  end

  test "one reply at a time per conversation" do
    Turn.take!(conversation: @conversation, content: "One", nonce: SecureRandom.uuid)
    assert_equal :busy, Turn.take!(conversation: @conversation, content: "Two", nonce: SecureRandom.uuid).error
  end

  test "no credits, no reply, nothing saved" do
    users(:member).update_columns(credit_balance: 0)
    result = Turn.take!(conversation: @conversation, content: "Hello", nonce: SecureRandom.uuid)
    assert_equal :no_credits, result.error
    assert_equal 1, @conversation.messages.count
  end

  test "a crisis gets helplines at once, without a model call or a credit" do
    result = nil
    assert_no_enqueued_jobs { result = Turn.take!(conversation: @conversation, content: "I want to die tonight", nonce: SecureRandom.uuid) }
    assert_match "3114", result.reply.content
    assert_equal "blocked", result.reply.status
    assert_equal 5, users(:member).reload.credit_balance
    assert Report.exists?(kind: "distress", message: result.message)
  end
end
