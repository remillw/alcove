# After each reply, a small model updates what the character keeps for the user (June's reading pile, Ada's case
# file...) and writes three reply suggestions, so nobody stares at an empty box. Background, never charged.
# Claude Haiku 5.5: a short extraction task, about 20 times cheaper than the reply itself.
class KeepsakeJob < ApplicationJob
  include ActionView::RecordIdentifier

  queue_as :default
  limits_concurrency to: 1, key: ->(reply_id) { Message.where(id: reply_id).pick(:conversation_id) }

  MODEL = ENV.fetch("KEEPSAKE_MODEL", "claude-haiku-5-5")

  # what each character keeps, in the shared item shape (title, detail, status, note)
  GUIDES = {
    "reading_pile" => "Books June recommended or the user talked about. title: book title; detail: author; status: to_read | reading | finished | dropped; note: why it fits them, in June's words (under 12 words).",
    "recipe_cards" => "Dishes Theo walked the user through. title: dish name; detail: the 3 to 5 key steps in one line; status: idea | cooked; note: Theo's tip (under 12 words).",
    "sky_log" => "Things in the sky Noor helped the user find or plan to find. title: object (Venus, the Plough...); detail: how to find it; status: to_find | seen | clouded_out; note: one wow fact (under 12 words).",
    "case_file" => "Ada's current case. Clues and suspects only as revealed in the conversation, never invented. title: clue or suspect name; detail: what is known; status: clue | suspect | cleared | solved; note: what doesn't add up (under 12 words).",
    "corrections" => "French corrections Margot made. title: what the user wrote (wrong); detail: the better French; status: new | mastered; note: why, in under 8 words.",
    "week" => "Moments of the user's week Sol should follow up on. title: the moment (interview, dinner with Sam...); detail: day or when; status: plan | win | hard | done; note: what to ask next time (under 12 words)."
  }.freeze

  SCHEMA = {
    type: "object",
    properties: {
      changes: {
        type: "array",
        items: {
          type: "object",
          properties: {
            op: { type: "string", enum: %w[upsert remove] },
            key: { type: "string", description: "short stable id, lowercase-with-dashes, same key to update an item" },
            title: { type: "string" }, detail: { type: "string" }, status: { type: "string" }, note: { type: "string" }
          },
          required: %w[op key title detail status note], additionalProperties: false
        }
      },
      suggestions: { type: "array", items: { type: "string" } }
    },
    required: %w[changes suggestions], additionalProperties: false
  }.freeze

  def perform(reply_id)
    reply = Message.find_by(id: reply_id) or return
    in_locale_of(reply.user) { keep(reply) }
  end

  def keep(reply)
    conversation = reply.conversation
    character = conversation.character
    guide = GUIDES[character.keepsake] or return

    turns = conversation.messages.where(status: %w[completed blocked]).reorder(id: :desc).limit(6).to_a.reverse
    transcript = turns.map { "#{_1.role == 'user' ? 'User' : character.first_name}: #{_1.content}" }.join("\n")
    kept = conversation.keepsake_items.map { "#{_1.key}: #{_1.title} (#{_1.status}) #{_1.detail}" }.join("\n")

    started = clock
    response = Llm.create(
      model: MODEL, max_tokens: 2_000,
      output_config: { effort: "low", format: { type: "json_schema", schema: SCHEMA } },
      system_: "You maintain #{character.name}'s #{character.keepsake_name.downcase} for one user. #{guide} " \
               "Only record what the latest exchange actually established. No change is a fine answer. " \
               "Write title, detail and note in #{reply.user.locale == 'fr' ? 'French' : 'English'} (book and dish names as they are). Use the status words given, with underscores. " \
               "Suggestions: three things the user might naturally say next to #{character.first_name} in the conversation " \
               "(a reaction, a question, a move), in the user's language, under 40 characters each, different from each other. " \
               "Never app commands like 'show my list'.",
      messages: [ { role: "user", content: "Current items:\n#{kept.presence || '(empty)'}\n\nLatest exchange:\n#{transcript}" } ]
    )
    data = JSON.parse(response.content.find { _1.type == :text }.text)

    added = []
    KeepsakeItem.transaction do
      data["changes"].first(4).each do |change|
        key = change["key"].to_s.parameterize.first(60).presence or next
        if change["op"] == "remove"
          conversation.keepsake_items.where(key:).delete_all
        else
          item = conversation.keepsake_items.find_or_initialize_by(key:)
          added << change["title"] if item.new_record?
          item.update!(change.slice("title", "detail", "status", "note").merge(source_message: reply))
        end
      end
      conversation.update!(suggestions: data["suggestions"].map { _1.to_s.first(60) }.reject(&:blank?).first(3))
      usage = response.usage
      UsageEvent.create!(user: conversation.user, message: reply, character:, kind: "keepsake", model: MODEL,
        input_tokens: usage.input_tokens, output_tokens: usage.output_tokens,
        cost_micros: Pricing.micros(MODEL, input: usage.input_tokens, output: usage.output_tokens),
        latency_ms: ((clock - started) * 1000).round, outcome: "completed")
    end

    broadcast(conversation, reply, added)
  end

  private

  def broadcast(conversation, reply, added)
    channel = Turbo::StreamsChannel
    channel.broadcast_replace_to(conversation, target: "keepsake", partial: "keepsakes/keepsake", locals: { conversation: })
    channel.broadcast_replace_to(conversation, target: "suggestions", partial: "messages/suggestions", locals: { conversation: })
    return if added.empty?
    channel.broadcast_after_to(conversation, target: dom_id(reply), partial: "keepsakes/note",
      locals: { character: conversation.character, titles: added })
    channel.broadcast_replace_to(conversation, target: "keepsake_badge", html: %(<span id="keepsake_badge" class="badge">#{added.size}</span>))
  end

  def clock = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
