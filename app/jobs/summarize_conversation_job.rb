# Every few exchanges, folds the conversation into a short summary and pulls out lasting facts ("has a dog called
# Biscuit"), so a character remembers weeks later without resending everything. Never charged to the user.
class SummarizeConversationJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(conversation_id) { conversation_id }

  SCHEMA = {
    type: "object",
    properties: {
      summary: { type: "string", description: "Updated summary of the whole relationship, at most 120 words, third person." },
      facts: {
        type: "array", maxItems: 5,
        items: {
          type: "object",
          properties: {
            fact: { type: "string", description: "One lasting fact about the user, under 20 words." },
            importance: { type: "integer", minimum: 1, maximum: 3 }
          },
          required: %w[fact importance], additionalProperties: false
        }
      }
    },
    required: %w[summary facts], additionalProperties: false
  }.freeze

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return unless conversation&.needs_summary?

    messages = conversation.messages.where(status: "completed").where("id > ?", conversation.summarized_until_message_id.to_i)
    transcript = messages.map { "#{_1.role == 'user' ? 'User' : conversation.character.first_name}: #{_1.content}" }.join("\n")
    known = conversation.memories.pluck(:fact)

    started = clock
    response = Llm.create(
      model: conversation.character.model, max_tokens: 4_000, output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
      system_: "You keep a character's notes about the person they talk to. Only keep what the user said about " \
               "themselves and wants remembered: no guesses, nothing about health or intimacy unless the user stated " \
               "it plainly, nothing the character said. Facts already known must not be repeated.",
      messages: [ { role: "user", content: "Previous summary: #{conversation.summary.presence || '(none)'}\n" \
                                           "Already known: #{known.join('; ').presence || '(none)'}\n\nNew transcript:\n#{transcript}" } ]
    )
    data = JSON.parse(response.content.find { _1.type == :text }.text)

    Conversation.transaction do
      conversation.update!(summary: data["summary"], summarized_until_message_id: messages.last.id)
      data["facts"].each { conversation.memories.create!(fact: _1["fact"], importance: _1["importance"], source_message: messages.last) }
      usage = response.usage
      UsageEvent.create!(user: conversation.user, character: conversation.character, kind: "summary",
        model: conversation.character.model, input_tokens: usage.input_tokens, output_tokens: usage.output_tokens,
        cost_micros: Pricing.micros(conversation.character.model, input: usage.input_tokens, output: usage.output_tokens),
        latency_ms: ((clock - started) * 1000).round, outcome: "completed")
    end
  end

  private def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
