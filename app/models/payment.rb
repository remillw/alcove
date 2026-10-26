# One attempt to buy a product. pending -> paid | failed | expired; paid -> partially_refunded -> refunded. Money wins over everything else:
# a late "paid" can still turn a failed or expired payment into a paid one (see Payments::Settlement).
class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :subscription, optional: true

  enum :status, %w[pending paid failed expired partially_refunded refunded].index_by(&:itself)

  before_validation { self.token ||= SecureRandom.uuid }
  validates :amount_cents, :credits, numericality: { greater_than: 0 }

  # still pending after the checkout session could have lasted: ask the provider what happened
  scope :stale, ->(age = 1.hour) { pending.where(created_at: ...age.ago) }

  # money was received at some point (and maybe returned since): the payment has left pending/failed/expired for good
  def settled? = paid? || partially_refunded? || refunded?

  def refundable_cents = amount_cents - refunded_cents

  # Credits that `refunded` cents of this payment represent: credits * refunded / amount, rounded half up. It is always
  # computed on the CUMULATIVE refunded total, never per refund, so the roundings can't drift: three partial refunds
  # add up to exactly what one refund of the same total would take, and a full refund takes exactly `credits`.
  def credits_for(refunded)
    (credits * refunded * 2 + amount_cents) / (2 * amount_cents)
  end

  def product = Payments::Product.find(product_key)
end
