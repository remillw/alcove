# Recall evaluation: can the engine bring back the right fact among 40? Facts and messages come from
# evals/memory/dataset.yml. For each engine available (full text always, embeddings when VOYAGE_API_KEY is set) it
# measures, over the messages:
#   recall@K  the expected fact is among the K most relevant facts (K = Recall::RELEVANT), the search alone
#   merged    the expected fact is in what the prompt would get (5 important + 8 relevant, Recall#memories)
#   baseline  the old rule: the 15 most important facts, no search (the same for every engine)
# Nothing is kept in the database (rolled back). The report goes to evals/memory/<date>.md.
module Evals
  class MemoryRecall
    DATASET = Rails.root.join("evals/memory/dataset.yml")

    def initialize(engines: nil)
      data = YAML.safe_load_file(DATASET)
      @facts = data.fetch("facts")
      @queries = data.fetch("queries")
      @engines = engines || (Embeddings.enabled? ? %i[fulltext embeddings] : %i[fulltext])
    end

    def run
      results = @engines.to_h { [ _1, measure(_1) ] }
      path = write(results)
      results.each { |engine, r| puts "#{engine}: recall@#{Recall::RELEVANT} #{r[:relevant_hits]}/#{@queries.size}, merged #{r[:merged_hits]}/#{@queries.size}" }
      puts "baseline (15 most important): #{baseline_hits}/#{@queries.size}"
      puts "Report: #{path}"
      results
    end

    def measure(engine)
      rows = nil
      ActiveRecord::Base.transaction do
        conversation = build_conversation
        embed_facts(conversation) if engine == :embeddings
        recall = Recall.new(conversation, engine: engine)
        rows = @queries.map do |q|
          expected = @facts.fetch(q["expects"])["text"]
          relevant = recall.relevant(q["text"]).map(&:fact)
          merged = recall.facts(q["text"])
          { query: q["text"], expected: expected, relevant: relevant.include?(expected), merged: merged.include?(expected),
            rank: relevant.index(expected)&.+(1) }
        end
        raise ActiveRecord::Rollback
      end
      { rows: rows, relevant_hits: rows.count { _1[:relevant] }, merged_hits: rows.count { _1[:merged] } }
    end

    private

    def build_conversation
      user = User.create!(adult_confirmed_at: Time.current)
      conversation = user.conversations.create!(character: Character.order(:id).first!)
      @facts.each_value { conversation.memories.create!(fact: _1["text"], importance: _1["importance"]) }
      conversation
    end

    def embed_facts(conversation)
      memories = conversation.memories.to_a
      vectors = Embeddings.embed(memories.map(&:fact), input_type: "document")
      memories.zip(vectors) { |memory, vector| memory.update_column(:embedding, vector) }
    end

    # the old rule, run for real on the same rows (importance, then newest): the same for every query
    def baseline_hits = @baseline_hits ||= compute_baseline_hits

    def compute_baseline_hits
      top = nil
      ActiveRecord::Base.transaction do
        top = build_conversation.memories.order(importance: :desc, id: :desc).limit(15).pluck(:fact)
        raise ActiveRecord::Rollback
      end
      @queries.count { top.include?(@facts.fetch(_1["expects"])["text"]) }
    end

    def write(results)
      path = Rails.root.join("evals/memory/#{Date.current.iso8601}.md")
      n = @queries.size
      lines = [ "# Memory recall eval #{Date.current.iso8601}", "",
                "#{@facts.size} facts, #{n} messages. Embedding model: #{Embeddings::MODEL} (#{Embeddings::DIMENSIONS} dimensions) when used.", "",
                "| Engine | recall@#{Recall::RELEVANT} (search alone) | merged (5 important + #{Recall::RELEVANT} relevant) |", "|---|---|---|",
                "| baseline: 15 most important, no search | - | #{pct(baseline_hits, n)} |" ]
      results.each { |engine, r| lines << "| #{engine} | #{pct(r[:relevant_hits], n)} | #{pct(r[:merged_hits], n)} |" }
      results.each do |engine, r|
        lines += [ "", "## #{engine}", "", "| Message | Expected fact | Rank | In prompt |", "|---|---|---|---|" ]
        r[:rows].each { lines << "| #{_1[:query]} | #{_1[:expected]} | #{_1[:rank] || 'miss'} | #{_1[:merged] ? 'yes' : 'no'} |" }
      end
      File.write(path, lines.join("\n") + "\n")
      path
    end

    def pct(hits, total) = "#{hits}/#{total} (#{(100.0 * hits / total).round}%)"
  end
end
