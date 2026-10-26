# The single door to the Anthropic API: replaced by a fake in tests (Llm.client = FakeLlm.new).
module Llm
  # Claude Opus 5.5 by default (thinking always on; "low" effort suits short chat replies).
  # LLM_MODEL switches every character to another model, e.g. claude-haiku-5-5 for a much lower cost per message.
  DEFAULT_MODEL = ENV.fetch("LLM_MODEL", "claude-opus-5-5")
  EFFORT = ENV.fetch("LLM_EFFORT", "low")

  class << self
    attr_writer :client

    def client
      @client ||= if ENV["ANTHROPIC_API_KEY"].blank? && Rails.env.development?
        Llm::Fake.new(delay: 0.04) # no key on this machine: scripted replies, same streaming path
      else
        Anthropic::Client.new(timeout: 60, max_retries: 0)
      end
    end

    def stream(**params) = client.messages.stream(**params)
    def create(**params) = client.messages.create(**params)
  end
end
