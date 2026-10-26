# Two ways to find a memory by meaning, both indexed:
#   - embedding (already there, never filled): HNSW with cosine distance, used when Voyage is configured
#   - fact_tsv: a generated full-text vector, the free fallback. The 'simple' config does no stemming and no stop
#     words, so it behaves the same for French and English. (unaccent is not immutable, so it cannot back a
#     generated column; accents are matched as typed.)
class AddRecallIndexesToMemories < ActiveRecord::Migration[8.1]
  def change
    add_index :memories, :embedding, using: :hnsw, opclass: :vector_cosine_ops, name: "index_memories_on_embedding_hnsw"

    add_column :memories, :fact_tsv, :virtual, type: :tsvector, as: "to_tsvector('simple', fact)", stored: true
    add_index :memories, :fact_tsv, using: :gin, name: "index_memories_on_fact_tsv"
  end
end
