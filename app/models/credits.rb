# The only way credits move. Every movement is a ledger entry with a unique idempotency key, written in the same
# transaction as the cached balance, under a row lock on the user: two tabs can't spend the same credit, and a
# replayed job can't charge or refund twice.
module Credits
  InsufficientBalance = Class.new(StandardError)

  # clamp: a debit that the balance can't cover takes what is left instead of raising (refunds: the credits may
  # already be spent, the balance still never goes below zero). The shortfall is written in the entry's metadata.
  def self.post!(user:, amount:, kind:, key:, message: nil, metadata: {}, clamp: false)
    User.transaction do
      user.lock!
      if (done = CreditEntry.find_by(idempotency_key: key))
        next done
      end
      if clamp && user.credit_balance + amount < 0
        metadata = metadata.merge(requested: amount, shortfall: -(user.credit_balance + amount))
        amount = -user.credit_balance
      end
      raise InsufficientBalance if user.credit_balance + amount < 0

      entry = CreditEntry.create!(user:, amount:, kind:, message:, idempotency_key: key, metadata:)
      user.update_columns(credit_balance: user.credit_balance + amount, updated_at: Time.current)
      entry
    end
  end

  # nightly check: the cached balance must equal the ledger
  def self.drifted_user_ids
    User.joins("LEFT JOIN credit_entries ON credit_entries.user_id = users.id")
      .group("users.id").having("users.credit_balance <> COALESCE(SUM(credit_entries.amount), 0)").pluck("users.id")
  end
end
