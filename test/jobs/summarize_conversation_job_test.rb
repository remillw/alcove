require "test_helper"

class SummarizeConversationJobTest < ActiveJob::TestCase
  test "folds the conversation into a summary and facts the user can see" do
    conversation = conversations(:member_june)
    Conversation::SUMMARY_EVERY.times { |i| conversation.messages.create!(role: i.even? ? "user" : "assistant", content: "line #{i}") }
    @llm.json = { summary: "Sam loves sea novels.", facts: [ { fact: "Reads on the train", importance: 2 } ] }.to_json

    SummarizeConversationJob.perform_now(conversation.id)

    assert_equal "Sam loves sea novels.", conversation.reload.summary
    assert_equal [ "Reads on the train" ], conversation.memories.pluck(:fact)
    assert_not conversation.needs_summary?
  end
end
