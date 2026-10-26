# One attempt to buy a product. pending -> paid | failed | expired; paid -> refunded. Money wins over everything else:
# a late "paid" can still turn a failed or expired payment into a paid one (see Payments::Settlement).
class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :subscription, optional: true

  enum :status, %w[pending paid failed expired refunded].index_by(&:itself)

  before_validation { self.token ||= SecureRandom.uuid }
  validates :amount_cents, :credits, numericality: { greater_than: 0 }

  # still pending after the checkout session could have lasted: ask the provider what happened
  scope :stale, ->(age = 1.hour) { pending.where(created_at: ...age.ago) }

  def product = Payments::Product.find(product_key)
end
