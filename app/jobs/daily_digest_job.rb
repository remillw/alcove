# Every evening: the day in numbers, for Rémi on Discord through Hermes.
class DailyDigestJob < ApplicationJob
  queue_as :default

  def perform(day = Date.current)
    range = day.all_day
    replies = UsageEvent.where(created_at: range, kind: "reply")
    cost = UsageEvent.where(created_at: range).sum(:cost_micros) / 1_000_000.0
    by_character = replies.joins(:character).group("characters.name").count.sort_by { -_2 }.map { "#{_1} #{_2}" }.join(", ")
    first_token = replies.where.not(first_token_ms: nil).pick(Arel.sql("percentile_cont(0.5) WITHIN GROUP (ORDER BY first_token_ms)"))
    Hermes.notify("daily_digest", title: "Bilan du #{I18n.l(day, format: '%d/%m')}", body: <<~TEXT.strip)
      Personnes actives : #{Conversation.joins(:messages).where(messages: { created_at: range, role: 'user' }).distinct.count(:user_id)} · inscriptions : #{User.where(registered_at: range).count}
      Réponses : #{replies.count} (échecs #{replies.where(outcome: 'failed').count}) · #{by_character.presence || 'aucune'}
      Coût API : #{format('%.2f', cost)} $ · premier mot médian : #{first_token ? "#{first_token.round} ms" : 'n/a'}
      Signalements : #{Report.where(created_at: range, kind: 'user_flag').count} · détresse : #{Report.where(created_at: range, kind: 'distress').count}
    TEXT
  end
end
