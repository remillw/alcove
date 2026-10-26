# Computes the embedding of one fact in the background, so a reply never waits for it. Idempotent: a fact that already
# has its vector is left alone, so retries and the backfill task can run it twice without a second API call.
class EmbedMemoryJob < ApplicationJob
  queue_as :default
  retry_on Embeddings::Error, wait: :polynomially_longer, attempts: 5
  discard_on ActiveJob::DeserializationError

  def perform(memory)
    return if memory.embedding.present? || !Embeddings.enabled?

    memory.update_column(:embedding, Embeddings.embed_one(memory.fact, input_type: "document"))
  end
end
