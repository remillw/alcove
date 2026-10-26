require "test_helper"

class RecoverStuckRepliesJobTest < ActiveJob::TestCase
  test "a reply stranded by a dead worker is failed, refunded once, and the conversation unblocked" do
    conversation = conversations(:member_june)
    reply = Turn.take!(conversation:, content: "Hello", nonce: SecureRandom.uuid).reply
    Message.where(id: reply.id).update_all(status: "streaming", updated_at: 10.minutes.ago)
    assert_equal 4, users(:member).reload.credit_balance

    2.times { RecoverStuckRepliesJob.perform_now }

    assert_equal "failed", reply.reload.status
    assert_equal 5, users(:member).reload.credit_balance
    assert_nil conversation.active_reply
  end

  test "a reply that stalls after its first part is refunded too, like any failure" do
    conversation = conversations(:member_june)
    reply = Turn.take!(conversation:, content: "Hello", nonce: SecureRandom.uuid).reply
    reply.update!(content: "First part.", status: "completed")
    part = conversation.messages.create!(role: "assistant", status: "streaming", model: reply.model, part_of_id: reply.id, content: "Half a")
    Message.where(id: part.id).update_all(updated_at: 10.minutes.ago)

    RecoverStuckRepliesJob.perform_now

    assert_equal "failed", part.reload.status
    assert_equal 5, users(:member).reload.credit_balance
  end

  test "a reply waiting its turn in a busy queue is left alone" do
    reply = Turn.take!(conversation: conversations(:member_june), content: "Hello", nonce: SecureRandom.uuid).reply
    Message.where(id: reply.id).update_all(updated_at: 5.minutes.ago)
    RecoverStuckRepliesJob.perform_now
    assert_equal "pending", reply.reload.status
  end

  test "a reply still being written is left alone" do
    reply = Turn.take!(conversation: conversations(:member_june), content: "Hello", nonce: SecureRandom.uuid).reply
    Message.where(id: reply.id).update_all(status: "streaming")
    RecoverStuckRepliesJob.perform_now
    assert_equal "streaming", reply.reload.status
  end
end
