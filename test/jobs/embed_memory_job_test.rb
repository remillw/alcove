require "test_helper"

class EmbedMemoryJobTest < ActiveJob::TestCase
  setup { @conversation = conversations(:member_june) }

  test "fills the vector once; running it again makes no second API call" do
    with_voyage(vectors: { "Has a dog called Biscuit" => 7 }) do
      memory = @conversation.memories.create!(fact: "Has a dog called Biscuit")

      EmbedMemoryJob.perform_now(memory)
      EmbedMemoryJob.perform_now(memory.reload)
      EmbedMemoryJob.perform_now(Memory.find(memory.id))

      assert_equal 1, @voyage_calls.size
      assert_equal 1.0, memory.reload.embedding[7]
    end
  end

  test "a new fact queues its embedding only when Voyage is configured" do
    without_voyage { assert_no_enqueued_jobs(only: EmbedMemoryJob) { @conversation.memories.create!(fact: "Likes tea") } }
    with_voyage { assert_enqueued_with(job: EmbedMemoryJob) { @conversation.memories.create!(fact: "Likes tea") } }
  end

  test "does nothing without a key" do
    memory = @conversation.memories.create!(fact: "Likes tea")
    without_voyage { EmbedMemoryJob.perform_now(memory) }
    assert_nil memory.reload.embedding
  end

  test "the HNSW and full-text indexes exist" do
    defs = Memory.connection.select_values("SELECT indexdef FROM pg_indexes WHERE tablename = 'memories'").join("\n")
    assert_match(/USING hnsw \(embedding vector_cosine_ops\)/, defs)
    assert_match(/USING gin \(fact_tsv\)/, defs)
  end
end
