# Stand-in for the Anthropic client: in tests, and in development when ANTHROPIC_API_KEY is not set.
# Streams scripted chunks with the same surface the jobs use (text, accumulated_message.usage, close, create).
module Llm
  class Fake
    Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, :cache_creation_input_tokens, keyword_init: true)
    Block = Struct.new(:type, :text)
    Response = Struct.new(:content, :usage)
    Stream = Struct.new(:chunks, :delay, :error_after, :usage) do
      def text
        Enumerator.new do |y|
          chunks.each_with_index do |chunk, i|
            raise error_after.last if error_after && i == error_after.first
            sleep delay if delay
            y << chunk
          end
        end
      end

      def accumulated_message = Response.new([], usage)
      def close = nil
    end

    attr_accessor :chunks, :delay, :error_after, :json, :requests

    def initialize(chunks: nil, delay: nil, error_after: nil, json: nil)
      @chunks = chunks || "Of course. Tell me a little more, and I'll remember it for next time.".scan(/\S+\s*/)
      @delay, @error_after, @json, @requests = delay, error_after, json, []
    end

    def messages = self

    def stream(**params)
      @requests << params
      Stream.new(chunks, delay, error_after, Usage.new(input_tokens: 1200, output_tokens: 40, cache_read_input_tokens: 900, cache_creation_input_tokens: 0))
    end

    def create(**params)
      @requests << params
      keepsake = params.dig(:output_config, :format, :schema, :properties)&.key?(:changes)
      body = json || if keepsake
        { changes: [ { op: "upsert", key: "piranesi", title: "Piranesi", detail: "Susanna Clarke", status: "to_read", note: "a house of tides and statues" } ],
          suggestions: [ "Tell me more", "Something lighter?", "I'll start tonight" ] }.to_json
                     else
        { summary: "They chatted about their week.", facts: [ { fact: "Likes long walks", importance: 2 } ] }.to_json
                     end
      Response.new([ Block.new(:text, body) ], Usage.new(input_tokens: 800, output_tokens: 60))
    end
  end
end
