# A worker that dies mid-stream (deploy, crash, lost database connection) leaves its reply "streaming" forever,
# and the unique index then blocks the whole conversation. Found by the load test (bench/, 26/10): with 50 LLM
# threads each holding connections to four databases, Postgres ran out of clients and 45 replies were stranded.
# Every minute: a reply untouched for STALE is failed and its credit refunded, like any failure in GenerateReplyJob
# (same idempotent key, so never twice).
class RecoverStuckRepliesJob < ApplicationJob
  include ActionView::RecordIdentifier
  queue_as :default

  STREAMING_STALE = 3.minutes # a stream never runs past GenerateReplyJob::DEADLINE (90 s)
  PENDING_STALE = 15.minutes  # under load a reply can wait its turn in the queue for a while

  def perform
    stale = Message.where(role: "assistant", status: "streaming", updated_at: ...STREAMING_STALE.ago)
      .or(Message.where(role: "assistant", status: "pending", updated_at: ...PENDING_STALE.ago))
    stale.find_each do |reply|
      next unless claim(reply)

      refund(reply.part_of_id ? Message.find(reply.part_of_id) : reply)
      in_locale_of(reply.user) do
        Turbo::StreamsChannel.broadcast_replace_to(reply.conversation, target: dom_id(reply), partial: "messages/message", locals: { message: reply.reload })
      end
    end
  end

  private

  def claim(reply)
    Message.where(id: reply.id, status: %w[pending streaming])
      .update_all(status: "failed", error_code: "stalled", updated_at: Time.current) == 1
  end

  # the credit is charged on the first message of a reply, even when a later part is the one that stalled
  def refund(first)
    Credits.post!(user: first.user, amount: 1, kind: :release, key: "reply:#{first.id}:release", message: first)
  end
end
