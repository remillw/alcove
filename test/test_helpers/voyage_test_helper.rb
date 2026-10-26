# Fake Voyage: no network. Each text becomes a one-hot-ish vector chosen by VOYAGE_VECTORS (text => axis), so a test
# decides which facts are "close" to which message.
module VoyageTestHelper
  Call = Struct.new(:payload, :key, keyword_init: true)

  def with_voyage(vectors: {}, status: 200)
    @voyage_calls = []
    previous = ENV["VOYAGE_API_KEY"]
    ENV["VOYAGE_API_KEY"] = "test-key"
    Embeddings.transport = lambda do |uri:, key:, payload:|
      @voyage_calls << Call.new(payload: payload, key: key)
      data = payload[:input].each_with_index.map { |text, i| { index: i, embedding: axis(vectors.fetch(text, 1023)) } }
      [ status, { data: data.reverse, usage: { total_tokens: 1 } }.to_json ] # reversed: the client must sort by index
    end
    yield
  ensure
    ENV["VOYAGE_API_KEY"] = previous
    Embeddings.transport = nil
  end

  def without_voyage
    previous = ENV.delete("VOYAGE_API_KEY")
    yield
  ensure
    ENV["VOYAGE_API_KEY"] = previous if previous
  end

  def axis(i) = Array.new(Embeddings::DIMENSIONS) { _1 == i ? 1.0 : 0.0 }
end
