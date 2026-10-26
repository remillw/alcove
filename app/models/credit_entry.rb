class CreditEntry < ApplicationRecord
  belongs_to :user
  belongs_to :message, optional: true

  enum :kind, %w[grant reserve release purchase adjustment].index_by(&:itself)

  def readonly? = persisted?
end
