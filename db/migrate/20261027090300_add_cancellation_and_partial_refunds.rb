# Cancellation is a flag at the provider ("stop at the end of the period"), mirrored here until the provider's
# deleted event moves the subscription to canceled. Partial refunds need a running total: refunded_cents is the money
# returned so far, credits_refunded the credits taken back for it (which can differ from the nominal share when the
# balance could not cover it: see Payments::Settlement.payment_refunded).
class AddCancellationAndPartialRefunds < ActiveRecord::Migration[8.1]
  def change
    add_column :subscriptions, :cancel_at_period_end, :boolean, null: false, default: false
    add_column :payments, :refunded_cents, :integer, null: false, default: 0
    add_column :payments, :credits_refunded, :integer, null: false, default: 0
    # status gains "partially_refunded" (a string column, no database constraint to change)
  end
end
