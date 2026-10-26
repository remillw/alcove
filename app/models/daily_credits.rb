# Free plan: a member's balance is topped up to DAILY_FLOOR once a day (one ledger entry per user per day).
module DailyCredits
  DAILY_FLOOR = 20

  def self.top_up(user, date: Date.current)
    return unless user&.registered? && user.credit_balance < DAILY_FLOOR
    Credits.post!(user:, amount: DAILY_FLOOR - user.credit_balance, kind: :grant, key: "daily:#{user.id}:#{date}")
  rescue ActiveRecord::RecordNotUnique
    nil # another tab topped up at the same moment
  end
end
