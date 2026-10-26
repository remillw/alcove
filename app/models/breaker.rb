# Spending circuit breaker: once today's real API cost passes DAILY_BUDGET_USD, new replies stop until midnight.
module Breaker
  def self.budget_micros = (ENV.fetch("DAILY_BUDGET_USD", "15").to_f * 1_000_000).round

  def self.open?
    Rails.cache.fetch("breaker:#{Date.current}", expires_in: 1.minute) do
      UsageEvent.where(created_at: Date.current.all_day).sum(:cost_micros) >= budget_micros
    end
  end
end
