# Text embeddings from Voyage AI (the provider Anthropic recommends), over plain Net::HTTP: no gem.
# Switched on only by VOYAGE_API_KEY; without it Recall falls back to PostgreSQL full-text search.
#
# API (docs.voyageai.com/reference/embeddings-api, checked 26/10/2026): POST https://api.voyageai.com/v1/embeddings
# with { input: [..], model:, input_type: "query" | "document", output_dimension: 1024 } and a Bearer key; the answer is
# { data: [{ embedding: [..], index: }], usage: { total_tokens: } }. Facts are embedded as "document", the text we
# search with as "query" (Voyage prepends a different instruction to each, which improves retrieval).
module Embeddings
  class Error < StandardError; end

  ENDPOINT = URI("https://api.voyageai.com/v1/embeddings")
  MODEL = ENV.fetch("VOYAGE_MODEL", "voyage-3.5-lite")
  DIMENSIONS = 1024 # must match memories.embedding vector(1024)
  BATCH = 128       # Voyage accepts up to 1,000 texts per call; stay well below the token limit

  class << self
    # tests swap the network for a callable: ->(request_hash) { [status, body_string] }
    attr_writer :transport

    def enabled? = ENV["VOYAGE_API_KEY"].present?

    # texts => array of 1024-float arrays, same order
    def embed(texts, input_type:)
      raise Error, "VOYAGE_API_KEY is not set" unless enabled?
      Array(texts).each_slice(BATCH).flat_map { embed_batch(_1, input_type) }
    end

    def embed_one(text, input_type:) = embed([ text ], input_type: input_type).first

    private

    def embed_batch(texts, input_type)
      status, body = transport.call(
        uri: ENDPOINT, key: ENV.fetch("VOYAGE_API_KEY"),
        payload: { input: texts, model: MODEL, input_type: input_type, output_dimension: DIMENSIONS, truncation: true }
      )
      raise Error, "Voyage answered #{status}" unless status.to_i == 200

      data = JSON.parse(body).fetch("data").sort_by { _1["index"] }
      raise Error, "Voyage returned #{data.size} vectors for #{texts.size} texts" unless data.size == texts.size
      data.map { _1.fetch("embedding") }
    rescue JSON::ParserError, KeyError => e
      raise Error, "unexpected Voyage answer: #{e.class}"
    end

    def transport = @transport || method(:http)

    def http(uri:, key:, payload:)
      request = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{key}")
      request.body = payload.to_json
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 3, read_timeout: 10) { _1.request(request) }
      [ response.code, response.body ]
    rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      raise Error, "Voyage unreachable: #{e.class}"
    end
  end
end
