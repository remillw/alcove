class Report < ApplicationRecord
  KINDS = %w[user_flag distress blocked_input blocked_output].freeze
  belongs_to :message, optional: true
  belongs_to :user, optional: true
  validates :kind, inclusion: { in: KINDS }
end
