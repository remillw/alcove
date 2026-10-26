namespace :memory do
  desc "Recall@K of each available engine on evals/memory/dataset.yml, report in evals/memory/<date>.md (VOYAGE_API_KEY adds embeddings)"
  task eval: :environment do
    Evals::MemoryRecall.new.run
  end

  desc "Embed the facts that have no vector yet (after setting VOYAGE_API_KEY for the first time)"
  task embed: :environment do
    abort "VOYAGE_API_KEY is not set" unless Embeddings.enabled?
    Memory.unembedded.find_each { EmbedMemoryJob.perform_later(_1) }
    puts "Queued #{Memory.unembedded.count} facts"
  end
end
