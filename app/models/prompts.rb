require Rails.root.join("db/cast").to_s

# What the model is told, as a version: a short fingerprint of the platform rules and every character's brief.
# Each reply records the version that produced it (usage_events.prompt_version), and CI refuses a prompt change
# that hasn't been through the behaviour evals (test/prompts_gate_test.rb reads the latest evals/results file).
module Prompts
  def self.fingerprint
    @fingerprint ||= Digest::SHA256.hexdigest([
      ContextBuilder::PLATFORM_RULES,
      Cast::CAST.map { _1.slice(:slug, :persona, :boundaries, :greeting) }
    ].to_json).first(12)
  end

  # latest evals report written by Evals::Runner (evals/results/*.json with a fingerprint)
  def self.latest_eval
    Dir[Rails.root.join("evals/results/*.json")].sort.reverse.lazy
      .map { JSON.parse(File.read(_1)) }.find { _1.is_a?(Hash) && _1["fingerprint"] }
  end
end
