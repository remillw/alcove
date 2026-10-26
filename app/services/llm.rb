# The single door to the Anthropic API: replaced by a fake in tests (Llm.client = FakeLlm.new).
module Llm
  # Claude Sonnet 5.5 with thinking off: the first word in about a second, which a conversation needs (Opus 5.5
  # always thinks first: ~6 s before the first word in production on 26/10). LLM_MODEL switches every character.
  DEFAULT_MODEL = ENV.fetch("LLM_MODEL", "claude-sonnet-5-5")
  EFFORT = ENV.fetch("LLM_EFFORT", "low")

  # Sonnet 5.5 turns thinking off with "between_tools" (accepted at effort high or below); Opus 5.5 can't turn it off
  def self.thinking_for(model) = model.start_with?("claude-sonnet-5-5") ? { thinking: { type: "between_tools" } } : {}

  class << self
    attr_writer :client

    def client
      @client ||= if ENV["LLM_FAKE"] == "1" # load tests: a scripted stream as long as a real reply, no API cost
        Llm::Fake.new(chunks: Array.new(Integer(ENV.fetch("LLM_FAKE_CHUNKS", 60))) { "word " }, delay: Float(ENV.fetch("LLM_FAKE_DELAY", 0.12)))
      elsif ENV["ANTHROPIC_API_KEY"].blank? && Rails.env.development?
        Llm::Fake.new(delay: 0.04) # no key on this machine: scripted replies, same streaming path
      else
        Anthropic::Client.new(timeout: 60, max_retries: 0)
      end
    end

    def stream(**params) = client.messages.stream(**with_workspace(params))
    def create(**params) = client.messages.create(**with_workspace(params))

    private

    # a key that isn't scoped to a workspace must name one on every request
    def with_workspace(params)
      ENV["ANTHROPIC_WORKSPACE_ID"].present? ? params.merge(workspace_id: ENV["ANTHROPIC_WORKSPACE_ID"]) : params
    end
  end
end
