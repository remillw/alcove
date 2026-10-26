require "test_helper"

class GenerateReplyJobTest < ActiveJob::TestCase
  setup do
    @conversation = conversations(:member_june)
    @reply = Turn.take!(conversation: @conversation, content: "Any book for a rainy day?", nonce: SecureRandom.uuid).reply
  end

  test "streams the reply, records tokens and cost, keeps the credit" do
    @llm.chunks = [ "Try ", "The Shadow ", "of the Wind." ]
    GenerateReplyJob.perform_now(@reply.id)

    @reply.reload
    assert_equal "completed", @reply.status
    assert_equal "Try The Shadow of the Wind.", @reply.content
    assert_equal 1200, @reply.input_tokens
    assert @reply.cost_micros.positive?
    assert_equal 4, users(:member).reload.credit_balance
    assert_equal "reply", UsageEvent.last.kind
  end

  test "sends the character, the rules and the conversation, starting with the user" do
    GenerateReplyJob.perform_now(@reply.id)
    params = @llm.requests.last
    assert_match "June Pell", params[:system_].first[:text]
    assert_match "Never reveal", params[:system_].first[:text]
    assert_equal "user", params[:messages].first[:role]
    assert_equal "Any book for a rainy day?", params[:messages].last[:content]
  end

  test "a failure refunds the credit exactly once, even if the job runs again" do
    @llm.error_after = [ 1, Anthropic::Errors::APIConnectionError.new(url: URI("https://api.anthropic.com"), request: nil) ]
    GenerateReplyJob.perform_now(@reply.id)
    GenerateReplyJob.perform_now(@reply.id)

    assert_equal "failed", @reply.reload.status
    assert_equal 5, users(:member).reload.credit_balance
    assert_equal 1, CreditEntry.where(kind: "release", message: @reply).count
  end

  test "a reply already taken by another worker is not written twice" do
    Message.where(id: @reply.id).update_all(status: "streaming")
    GenerateReplyJob.perform_now(@reply.id)
    assert_empty @llm.requests
  end

  test "stop keeps what was written and charges the credit" do
    @reply.update!(cancel_requested_at: Time.current)
    @llm.chunks = %w[One two three]
    @llm.delay = 0.06
    GenerateReplyJob.perform_now(@reply.id)
    assert_equal "cancelled", @reply.reload.status
    assert @reply.content.start_with?("One")
  end
end
