class Memory < ApplicationRecord
  has_neighbors :embedding

  belongs_to :conversation
  belongs_to :source_message, class_name: "Message", optional: true

  validates :fact, presence: true, length: { maximum: 300 }
  scope :unembedded, -> { where(embedding: nil) }

  after_create_commit { EmbedMemoryJob.perform_later(self) if Embeddings.enabled? }
end
