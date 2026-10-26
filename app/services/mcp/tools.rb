# Read-only tools for operations agents (Hermes). Numbers and ids only: never the text of a conversation, a
# memory or a report, never an email address. Each tool is a name, a JSON schema and a lambda returning a Hash.
module Mcp
  module Tools
    module_function

    def days_param = { days: { type: "integer", description: "Window in days, 1 to 90 (default 7)" } }
    def window(args) = (Integer(args["days"] || 7).clamp(1, 90).days.ago..)

    TOOLS = {
      "usage_summary" => {
        description: "Activity, replies, failures, API cost and latency over the last N days, overall and per character.",
        schema: { type: "object", properties: days_param, additionalProperties: false },
        call: ->(args) {
          range = window(args)
          replies = UsageEvent.where(kind: "reply", created_at: range)
          {
            active_users: Message.where(role: "user", created_at: range).joins(:conversation).distinct.count("conversations.user_id"),
            signups: User.where(registered_at: range).count,
            replies: replies.count,
            failed: replies.where(outcome: "failed").count,
            api_cost_usd: (UsageEvent.where(created_at: range).sum(:cost_micros) / 1_000_000.0).round(2),
            first_token_ms: percentiles(replies, :first_token_ms),
            by_character: replies.joins(:character).group("characters.slug").count
          }
        }
      },
      "character_report" => {
        description: "One character over the last N days: replies, average reply length in words, keepsake items, reports and returning users.",
        schema: { type: "object", properties: { slug: { type: "string", description: "june, theo, noor, ada, margot or sol" }, **days_param }, required: [ "slug" ], additionalProperties: false },
        call: ->(args) {
          range = window(args)
          character = Character.find_by!(slug: args["slug"])
          messages = Message.joins(:conversation).where(conversations: { character_id: character.id }, created_at: range)
          {
            character: character.slug,
            conversations_active: messages.distinct.count(:conversation_id),
            replies: messages.where(role: "assistant", status: "completed").count,
            avg_reply_words: messages.where(role: "assistant", status: "completed").pick(Arel.sql("round(avg(array_length(regexp_split_to_array(trim(content), '\\s+'), 1)))")).to_i,
            keepsake_items: KeepsakeItem.joins(:conversation).where(conversations: { character_id: character.id }, created_at: range).count,
            reports: Report.joins(message: :conversation).where(conversations: { character_id: character.id }, created_at: range).group(:kind).count,
            users_back_after_a_day: Conversation.where(character:).where("last_message_at > created_at + interval '1 day'").where(last_message_at: range).count
          }
        }
      },
      "prompt_versions" => {
        description: "Compare prompt versions on real traffic: replies, failure rate, mean latency and cost per version.",
        schema: { type: "object", properties: days_param, additionalProperties: false },
        call: ->(args) {
          rows = UsageEvent.where(kind: "reply", created_at: window(args)).where.not(prompt_version: nil).group(:prompt_version)
            .pluck(:prompt_version, Arel.sql("count(*)"), Arel.sql("count(*) filter (where outcome = 'failed')"), Arel.sql("round(avg(latency_ms))"), Arel.sql("sum(cost_micros)"))
          { current: Prompts.fingerprint,
            versions: rows.map { |v, n, failed, latency, cost| { version: v, replies: n, failure_rate: (failed.to_f / n).round(3), mean_latency_ms: latency.to_i, cost_usd: (cost / 1_000_000.0).round(2) } } }
        }
      },
      "latest_evals" => {
        description: "Latest behaviour evals (pass/fail per case and character) and latest simulated-user scores.",
        schema: { type: "object", properties: {}, additionalProperties: false },
        call: ->(_args) {
          report = Prompts.latest_eval
          sims = Dir[Rails.root.join("evals/simulations/*.json")].max
          sim = sims && JSON.parse(File.read(sims))
          {
            evals: report && { fingerprint: report["fingerprint"], current: report["fingerprint"] == Prompts.fingerprint,
                               passed: report["results"].count { _1["pass"] }, total: report["results"].size,
                               failures: report["results"].reject { _1["pass"] }.map { { character: _1["character"], case: _1["case"], reason: _1["reason"] } } },
            simulation: sim && sim.group_by { _1["character"] }.transform_values { |rows|
              %w[makes_sense adapts human voice brevity].index_with { |axis| (rows.sum { _1["critique"][axis] } / rows.size.to_f).round(1) }
            }
          }
        }
      },
      "open_reports" => {
        description: "Unresolved reports (user flags, distress, blocked messages): counts by kind and character, with ids, never their text.",
        schema: { type: "object", properties: {}, additionalProperties: false },
        call: ->(_args) {
          open = Report.where(resolved_at: nil).includes(message: { conversation: :character })
          { total: open.size, by_kind: open.group_by(&:kind).transform_values(&:size),
            items: open.order(created_at: :desc).limit(50).map { { id: _1.id, kind: _1.kind, character: _1.message&.conversation&.character&.slug, at: _1.created_at.iso8601 } } }
        }
      }
    }.freeze

    PERCENTILES = {
      first_token_ms: [ "percentile_cont(0.5) within group (order by first_token_ms)", "percentile_cont(0.95) within group (order by first_token_ms)" ],
      latency_ms: [ "percentile_cont(0.5) within group (order by latency_ms)", "percentile_cont(0.95) within group (order by latency_ms)" ]
    }.freeze

    def percentiles(scope, column)
      p50, p95 = scope.where.not(column => nil).pick(*PERCENTILES.fetch(column).map { Arel.sql(_1) })
      { p50: p50&.round, p95: p95&.round }
    end
  end
end
