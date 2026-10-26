# Real cost of a call, in millionths of a dollar (integers, never floats in the database).
# Anthropic list prices per million tokens; cache writes cost 1.25x input, cache reads 0.1x input.
module Pricing
  PER_MILLION = {
    "claude-opus-5-5"   => { input: 4.00, output: 20.00 },
    "claude-sonnet-5-5" => { input: 2.00, output: 10.00 },
    "claude-haiku-5-5"  => { input: 0.10, output: 0.50 }
  }.freeze

  def self.micros(model, input: 0, output: 0, cache_read: 0, cache_write: 0)
    price = PER_MILLION.fetch(model) { PER_MILLION.fetch("claude-opus-5-5") }
    (input * price[:input] + cache_write * price[:input] * 1.25 + cache_read * price[:input] * 0.1 +
      output * price[:output]).round
  end
end
