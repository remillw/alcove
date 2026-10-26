class Memory < ApplicationRecord
  belongs_to :conversation
  belongs_to :source_message, class_name: "Message", optional: true

  validates :fact, presence: true, length: { maximum: 300 }
  scope :for_prompt, -> { order(importance: :desc, id: :desc).limit(15) }
end
