# Writes a character's reply with the streaming API and shows it word by word in the browser (Turbo Streams over
# Action Cable). A reply can come as two or three short messages: the model puts a line with "~" between them,
# and each part becomes its own message (part_of_id points to the first), still one credit.
# Invariants: one reply in progress per conversation (unique index), one credit charged per reply and refunded
# exactly once if nothing came back (idempotency keys), never more than DEADLINE seconds.
class GenerateReplyJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :llm
  limits_concurrency to: 1, key: ->(reply_id) { Message.where(id: reply_id).pick(:conversation_id) }

  FLUSH_EVERY = 0.05 # seconds: chunks are grouped so the browser gets ~20 updates a second at most
  DEADLINE = 90
  SEPARATOR = /\n[ \t]*~[ \t]*\n/
  MAX_PARTS = 3

  def perform(reply_id)
    in_locale_of(Message.find_by(id: reply_id)&.user) { stream_reply(reply_id) }
  end

  # the rescue clauses below belong to this method
  def stream_reply(reply_id)
    @reply = Message.find_by(id: reply_id)
    return unless @reply && Message.where(id: @reply.id, status: "pending").update_all(status: "streaming") == 1

    @reply.reload
    @started = clock
    @first_token = nil
    @part = @reply
    @parts = [ @reply ]
    @text = +""   # the current part
    @sent = 0     # characters of the current part already in the browser
    last_flush = 0.0
    stopped = false
    stream = Llm.stream(**ContextBuilder.new(@reply.conversation).params)

    stream.text.each do |chunk|
      @first_token ||= clock - @started
      @text << chunk
      split_parts
      next if clock - last_flush < FLUSH_EVERY

      last_flush = clock
      flush
      if cancel_requested? || clock - @started > DEADLINE
        stopped = true
        break
      end
    end
    flush

    usage = stopped ? nil : stream.accumulated_message.usage
    stream.close if stopped && stream.respond_to?(:close)
    finish(usage, stopped ? "cancelled" : "completed")
  rescue Anthropic::Errors::RateLimitError, Anthropic::Errors::InternalServerError, Anthropic::Errors::APIConnectionError => e
    fail_reply(e.class.name.demodulize.underscore)
  rescue Anthropic::Errors::APIStatusError => e
    Rails.error.report(e, context: { reply_id: })
    fail_reply("api_error")
  end

  private

  # "~" on its own line: close this message, open the next one (as a real person sending two texts)
  def split_parts
    while @parts.size < MAX_PARTS && (match = @text.match(SEPARATOR))
      before, after = match.pre_match.strip, match.post_match
      next @text = after if before.empty?

      @part.update!(content: before, status: "completed")
      show(@part)
      @part = @reply.conversation.messages.create!(role: "assistant", status: "streaming", model: @reply.model, part_of_id: @reply.id)
      Turbo::StreamsChannel.broadcast_append_to(@reply.conversation, target: "log", partial: "messages/message", locals: { message: @part })
      @parts << @part
      @text = after.lstrip
      @sent = 0
    end
  end

  def flush
    fresh = @text[@sent..]
    return if fresh.blank?
    Turbo::StreamsChannel.broadcast_append_to(@reply.conversation, target: dom_id(@part, :body), partial: "messages/chunk", locals: { text: fresh })
    @sent = @text.size
  end

  def finish(usage, status)
    input = usage&.input_tokens.to_i
    all_text = (@parts[0...-1].map(&:content) << @text).join("\n")
    output = usage ? usage.output_tokens.to_i : (all_text.size / 4.0).ceil # estimated when cancelled mid-way
    cache_read = usage&.cache_read_input_tokens.to_i
    cache_write = usage&.cache_creation_input_tokens.to_i
    cost = Pricing.micros(@reply.model, input:, output:, cache_read:, cache_write:)

    Message.transaction do
      if @text.strip.empty? && @part != @reply
        @part.destroy! # a trailing "~" with nothing after it
        @parts.pop
      else
        @part.update!(content: @text.strip, status:)
      end
      @reply.update!(input_tokens: input, output_tokens: output, cache_read_tokens: cache_read, cost_micros: cost)
      record_usage(input:, output:, cache_read:, cache_write:, cost:, outcome: status)
      refund if all_text.blank?
    end
    @parts.each { show(_1) }
    show_credits
    conversation = @reply.conversation
    KeepsakeJob.perform_later(@reply.id) if status == "completed" && all_text.present?
    SummarizeConversationJob.perform_later(conversation.id) if conversation.needs_summary?
  end

  def fail_reply(code)
    return unless @reply
    Message.transaction do
      (@part || @reply).update!(status: "failed", content: @text.to_s.strip, error_code: code)
      record_usage(input: 0, output: 0, cache_read: 0, cache_write: 0, cost: 0, outcome: "failed")
      refund
    end
    show(@part || @reply)
    show_credits
  end

  def refund
    Credits.post!(user: @reply.user, amount: 1, kind: :release, key: "reply:#{@reply.id}:release", message: @reply)
  end

  def record_usage(input:, output:, cache_read:, cache_write:, cost:, outcome:)
    UsageEvent.create!(user: @reply.user, message: @reply, character: @reply.character, kind: "reply", model: @reply.model,
      input_tokens: input, output_tokens: output, cache_read_tokens: cache_read, cache_write_tokens: cache_write,
      cost_micros: cost, outcome:, latency_ms: ((clock - @started) * 1000).round,
      first_token_ms: @first_token && (@first_token * 1000).round)
  end

  def show(message)
    message.reload
    Turbo::StreamsChannel.broadcast_replace_to(message.conversation, target: dom_id(message),
      partial: "messages/message", locals: { message: })
  end

  def show_credits
    Turbo::StreamsChannel.broadcast_replace_to(@reply.user, target: "credits",
      partial: "shared/credits", locals: { user: @reply.user.reload })
  end

  def cancel_requested? = Message.where(id: @reply.id).where.not(cancel_requested_at: nil).exists?
  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
