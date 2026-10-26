# Our mirror of a subscription held by the provider (which stays the source of truth).
class Subscription < ApplicationRecord
  belongs_to :user
  has_many :payments, dependent: :nullify

  enum :status, %w[active past_due canceled].index_by(&:itself)

  def product = Payments::Product.find(product_key)
end
