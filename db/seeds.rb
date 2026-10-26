# The opening cast. Idempotent: run again to update the texts without touching conversations.
# Voices were rewritten after the v2 round table (26/10): short, specific, a life that goes on between visits,
# and memory shown as shared ground ("so, Piranesi?"), never as a database ("I remember you said").

require_relative "cast"

Cast::CAST.each_with_index do |attrs, index|
  character = Character.find_or_initialize_by(slug: attrs[:slug])
  character.update!(attrs.merge(position: index, published: true, model: Llm::DEFAULT_MODEL, translations: Cast::TRANSLATIONS.fetch(attrs[:slug])))
end
puts "#{Character.published.count} characters"
