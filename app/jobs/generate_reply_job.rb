# Writes a character's reply with the streaming API and shows it word by word in the browser (Turbo Streams over
# Action Cable). Invariants: one reply in progress per conversation (unique index), one credit charged per reply
# and refunded exactly once if nothing useful came back (idempotency keys), never more than DEADLINE seconds.
class GenerateReplyJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :llm
  limits_concurrency to: 1, key: ->(reply_id) { Message.where(id: reply_id).pick(:conversation_id) }

  FLUSH_EVERY = 0.05 # seconds: chunks are grouped so the browser gets ~20 updates a second at most
  DEADLINE = 90

  def perform(reply_id)
    reply = Message.find_by(id: reply_id)
    return unless reply && Message.where(id: reply.id, status: "pending").update_all(status: "streaming") == 1

    reply.reload
    @started = clock
    @first_token = nil
    text = +""
    pending = +""
    last_flush = 0.0
    stream = Llm.stream(**ContextBuilder.new(reply.conversation).params)
    stopped = false

    stream.text.each do |chunk|
      @first_token ||= clock - @started
      text << chunk
      pending << chunk
      next if clock - last_flush < FLUSH_EVERY

      last_flush = clock
      append(reply, pending)
      pending = +""
      if cancel_requested?(reply) || clock - @started > DEADLINE
        stopped = true
        break
      end
    end
    append(reply, pending) if pending.present?

    usage = stopped ? nil : stream.accumulated_message.usage
    stream.close if stopped && stream.respond_to?(:close)
    finish(reply, text, usage, stopped ? "cancelled" : "completed")
  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError, Anthropic::Errors::APIConnectionError => e
    fail_reply(reply, text, e.class.name.demodulize.underscore)
  rescue Anthropic::Errors::APIStatusError => e
    Rails.error.report(e, context: { reply_id: })
    fail_reply(reply, text, "api_error")
  end

  private

  def finish(reply, text, usage, status)
    input = usage&.input_tokens.to_i
    output = usage ? usage.output_tokens.to_i : (text.size / 4.0).ceil # estimated when cancelled mid-way
    cache_read = usage&.cache_read_input_tokens.to_i
    cache_write = usage&.cache_creation_input_tokens.to_i
    cost = Pricing.micros(reply.model, input:, output:, cache_read:, cache_write:)

    Message.transaction do
      reply.update!(content: text.strip, status:, input_tokens: input, output_tokens: output,
        cache_read_tokens: cache_read, cost_micros: cost)
      record_usage(reply, input:, output:, cache_read:, cache_write:, cost:, outcome: status)
      refund(reply) if text.blank?
    end
    show(reply)
    SummarizeConversationJob.perform_later(reply.conversation_id) if reply.conversation.needs_summary?
  end

  def fail_reply(reply, text, code)
    return unless reply
    Message.transaction do
      reply.update!(status: "failed", content: text.to_s.strip, error_code: code)
      record_usage(reply, input: 0, output: 0, cache_read: 0, cache_write: 0, cost: 0, outcome: "failed")
      refund(reply)
    end
    show(reply)
  end

  def refund(reply)
    Credits.post!(user: reply.user, amount: 1, kind: :release, key: "reply:#{reply.id}:release", message: reply)
  end

  def record_usage(reply, input:, output:, cache_read:, cache_write:, cost:, outcome:)
    UsageEvent.create!(user: reply.user, message: reply, character: reply.character, kind: "reply", model: reply.model,
      input_tokens: input, output_tokens: output, cache_read_tokens: cache_read, cache_write_tokens: cache_write,
      cost_micros: cost, outcome:, latency_ms: ((clock - @started) * 1000).round,
      first_token_ms: @first_token && (@first_token * 1000).round)
  end

  def append(reply, chunk)
    return if chunk.empty?
    Turbo::StreamsChannel.broadcast_append_to(reply.conversation, target: dom_id(reply, :body),
      partial: "messages/chunk", locals: { text: chunk })
  end

  def show(reply)
    reply.reload
    Turbo::StreamsChannel.broadcast_replace_to(reply.conversation, target: dom_id(reply),
      partial: "messages/message", locals: { message: reply })
    Turbo::StreamsChannel.broadcast_replace_to(reply.user, target: "credits",
      partial: "shared/credits", locals: { user: reply.user.reload })
  end

  def cancel_requested?(reply) = Message.where(id: reply.id).where.not(cancel_requested_at: nil).exists?
  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
