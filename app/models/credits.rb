# The only way credits move. Every movement is a ledger entry with a unique idempotency key, written in the same
# transaction as the cached balance, under a row lock on the user: two tabs can't spend the same credit, and a
# replayed job can't charge or refund twice.
module Credits
  InsufficientBalance = Class.new(StandardError)

  def self.post!(user:, amount:, kind:, key:, message: nil, metadata: {})
    User.transaction do
      user.lock!
      if (done = CreditEntry.find_by(idempotency_key: key))
        next done
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
