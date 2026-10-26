class KeepsakeItem < ApplicationRecord
  belongs_to :conversation
  belongs_to :source_message, class_name: "Message", optional: true
  validates :key, :title, presence: true
end
