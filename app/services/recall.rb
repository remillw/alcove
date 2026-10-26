# Which remembered facts go into the <memory> block of one reply.
#
# Merge rule (documented, tested): the IMPORTANT facts always come first (the 5 the user would be most upset to see
# forgotten: name of the dog, their job...), then the facts most RELEVANT to what the user just said, found by meaning.
# Relevant facts already among the important ones are skipped (not counted), so the result has at most
# 5 + 8 = 13 facts, about 250 tokens: close to the 15 facts of the old "most important only" rule, but the right ones.
#
# Two engines, same contract (an ordered relation of Memory, best first):
#   :embeddings  Voyage vectors + pgvector HNSW cosine search, when VOYAGE_API_KEY is set
#   :fulltext    PostgreSQL tsvector search, free, always available
# A failing embeddings call never breaks a reply: it falls back to full text.
class Recall
  IMPORTANT = 5
  RELEVANT = 8
  CONTEXT_MESSAGES = 3     # the last user message plus the two before it, for "and what about her?" style follow-ups
  CONTEXT_CHARS = 600

  def self.engine = Embeddings.enabled? ? :embeddings : :fulltext

  def initialize(conversation, engine: self.class.engine)
    @conversation = conversation
    @engine = engine
  end

  # array of fact strings, important first
  def facts(query = query_text) = memories(query).map(&:fact)

  def memories(query = query_text)
    scope = @conversation.memories
    important = scope.order(importance: :desc, id: :desc).limit(IMPORTANT).to_a
    return important if query.blank?

    relevant = relevant(query, exclude: important.map(&:id))
    important + relevant
  end

  # the K most relevant facts, best first, whichever engine; also what the eval measures
  def relevant(query, limit: RELEVANT, exclude: [])
    scope = @conversation.memories
    scope = scope.where.not(id: exclude) if exclude.any?
    case @engine
    when :embeddings then by_embedding(scope, query, limit)
    else Recall::Fulltext.search(scope, query, limit)
    end
  rescue Embeddings::Error => e
    Rails.logger.warn("Recall: embeddings unavailable (#{e.message}), using full text")
    Recall::Fulltext.search(scope, query, limit)
  end

  private

  def by_embedding(scope, query, limit)
    vector = Embeddings.embed_one(query, input_type: "query")
    # iterative scan: with the conversation filter, a plain HNSW scan could stop after 40 candidates of other users
    Memory.transaction do
      Memory.connection.execute("SET LOCAL hnsw.iterative_scan = relaxed_order")
      scope.where.not(embedding: nil).nearest_neighbors(:embedding, vector, distance: "cosine").first(limit)
    end
  end

  # latest user message first, then a little of what came before, so the search sees the topic
  def query_text
    recent = @conversation.messages.where(status: "completed").reorder(id: :desc).limit(CONTEXT_MESSAGES + 2).to_a
    last_user = recent.find { _1.role == "user" } or return nil
    older = recent.reject { _1 == last_user || _1.id > last_user.id }.first(CONTEXT_MESSAGES - 1)
    [ last_user, *older ].map(&:content).join("\n").first(CONTEXT_CHARS)
  end
end
