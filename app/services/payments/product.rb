# The catalogue lives in code: the browser only ever sends a product key, never an amount or a number of credits.
module Payments
  Product = Data.define(:key, :kind, :name, :credits, :amount_cents, :currency) do
    def subscription? = kind == :subscription
    def price = amount_cents / 100.0
  end

  class Product
    ALL = [
      new(key: "pack_50", kind: :pack, name: "50 credits", credits: 50, amount_cents: 499, currency: "EUR"),
      new(key: "pack_150", kind: :pack, name: "150 credits", credits: 150, amount_cents: 1199, currency: "EUR"),
      # credits are granted again every period, not once
      new(key: "regular", kind: :subscription, name: "Regular (300 credits per month)", credits: 300, amount_cents: 999, currency: "EUR")
    ].freeze

    def self.all = ALL
    def self.packs = ALL.reject(&:subscription?)
    def self.subscription = ALL.find(&:subscription?)
    def self.find(key) = ALL.find { _1.key == key.to_s } || raise(UnknownProduct, "unknown product #{key.inspect}")
  end
end
