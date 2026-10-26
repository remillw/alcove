# Free fallback: PostgreSQL full-text search over memories.fact_tsv (generated column, GIN index, 'simple' config so
# French and English behave the same). The question is turned into an OR of its meaningful words, because a fact
# rarely shares every word with the message; ts_rank puts the facts that share the most (and the rarest) words first.
class Recall
  module Fulltext
    # words that match half of all facts and say nothing (English and French)
    STOP_WORDS = %w[
      the and for are but not you your with this that have has had was were what when where who how why can could
      would should about from they them their there here been being just like some any all out too very also into
      les des une que qui quoi est sont pas pour dans sur avec mais vous nous ils elles ont avez avons tu toi moi mon
      ton son mes tes ses ces cet cette aux par plus tout tous comme fait faire suis etes sommes etre avoir ici
      oui non bien tres alors donc car ainsi aussi quand dont
    ].to_set.freeze
    MIN_LENGTH = 3

    def self.search(scope, text, limit)
      terms = terms(text)
      return [] if terms.empty?

      tsquery = terms.map { "#{_1}:*" }.join(" | ") # prefix match: "marath" finds "marathon", "voyage" finds "voyages"
      query = Memory.sanitize_sql_array([ "to_tsquery('simple', ?)", tsquery ])
      scope.where("fact_tsv @@ #{query}").reorder(Arel.sql("ts_rank(fact_tsv, #{query}) DESC, importance DESC, id DESC")).limit(limit).to_a
    end

    # lowercase alphanumeric words only (so nothing can break the tsquery syntax), plurals folded, no stop words
    def self.terms(text)
      text.to_s.downcase.scan(/[[:alnum:]]+/).filter_map do |word|
        next if word.size < MIN_LENGTH || STOP_WORDS.include?(word)
        word.size > 4 ? word.delete_suffix("s").delete_suffix("x") : word
      end.uniq.first(30)
    end
  end
end
