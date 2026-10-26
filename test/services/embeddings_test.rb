require "test_helper"

class EmbeddingsTest < ActiveSupport::TestCase
  test "is off without a key and refuses to call the network" do
    without_voyage do
      assert_not Embeddings.enabled?
      assert_raises(Embeddings::Error) { Embeddings.embed([ "x" ], input_type: "query") }
    end
  end

  test "sends the documented request and returns vectors in input order" do
    with_voyage(vectors: { "a" => 1, "b" => 2 }) do
      vectors = Embeddings.embed(%w[a b], input_type: "document")

      assert_equal [ 1, 2 ], vectors.map { _1.index(1.0) }
      call = @voyage_calls.sole
      assert_equal "test-key", call.key
      assert_equal %w[a b], call.payload[:input]
      assert_equal "document", call.payload[:input_type]
      assert_equal 1024, call.payload[:output_dimension]
      assert_equal "voyage-3.5-lite", call.payload[:model]
    end
  end

  test "an error status raises, so callers can fall back" do
    with_voyage(status: 401) { assert_raises(Embeddings::Error) { Embeddings.embed_one("a", input_type: "query") } }
  end
end
