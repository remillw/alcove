class UsageEvent < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :message, optional: true
  belongs_to :character, optional: true
end
