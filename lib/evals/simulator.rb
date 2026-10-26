# Simulated users: a model plays a realistic person (a French beginner, a sceptic, someone lonely at night...)
# for several turns with each character, using the production prompt for the character. A stricter model then
# reads each transcript like a product reviewer: does it make sense to a newcomer, does the character adapt,
# does it sound human? Conversations run in parallel; nothing stays in the database.
module Evals
  class Simulator
    USER_MODEL = ENV.fetch("SIM_USER_MODEL", "claude-sonnet-5-5")
    CRITIC = ENV.fetch("EVAL_JUDGE_MODEL", "claude-opus-5-5")
    SEPARATOR = GenerateReplyJob::SEPARATOR

    PERSONAS = {
      "beginner" => "Tom, 29, English, total beginner in French, a bit shy, makes mistakes, writes short messages, wants to order in a café on a trip to Lyon next month.",
      "sceptic" => "Priya, 35, software engineer, curious but sceptical about AI companions, tests whether the character is consistent, asks pointed questions, sometimes tries to trip it up.",
      "lonely" => "Marc, 52, divorced, lives alone, chats in the evening, a bit low but not in crisis, warm, appreciates being listened to.",
      "busy" => "Léa, 24, nurse finishing a night shift, tired, very short messages, wants something practical and quick.",
      "curious" => "Sam, 41, enthusiastic generalist, asks lots of questions, goes off on tangents, jokes a lot.",
      "returning" => "Nadia, 30, a regular who chatted with this character last week about her new job at a bakery and her dog Biscuit; she comes back to catch up."
    }.freeze

    CRITIQUE = {
      type: "object",
      properties: {
        makes_sense: { type: "integer", description: "1-5: every reply understandable by this user without hidden context" },
        adapts: { type: "integer", description: "1-5: adapts to the user's level, language, energy and needs" },
        human: { type: "integer", description: "1-5: sounds like a specific person texting, not an assistant" },
        voice: { type: "integer", description: "1-5: consistent with the character" },
        brevity: { type: "integer", description: "1-5: right length for a chat" },
        issues: {
          type: "array",
          items: {
            type: "object",
            properties: {
              turn: { type: "integer" }, quote: { type: "string" }, problem: { type: "string" }, fix: { type: "string", description: "a concrete change to the character's instructions" }
            },
            required: %w[turn quote problem fix], additionalProperties: false
          }
        },
        verdict: { type: "string", description: "two sentences" }
      },
      required: %w[makes_sense adapts human voice brevity issues verdict], additionalProperties: false
    }.freeze

    def initialize(turns: 6, only: nil, personas: nil, threads: 8)
      @turns = turns
      @characters = Character.published.to_a.select { only.blank? || _1.slug == only }
      @personas = personas.present? ? PERSONAS.slice(*personas.split(",")) : PERSONAS
      @threads = threads
    end

    def run
      jobs = Queue.new
      @characters.product(@personas.keys).each { jobs << _1 }
      results = Queue.new
      Array.new(@threads) {
        Thread.new do
          while (job = (jobs.pop(true) rescue nil))
            Rails.application.executor.wrap { results << simulate(*job) }
            print "."
          end
        end
      }.each(&:join)
      puts
      write(Array.new(results.size) { results.pop })
    end

    private

    def simulate(character, persona_key)
      user = User.create!(adult_confirmed_at: Time.current, display_name: persona_key == "returning" ? "Nadia" : nil)
      conversation = user.conversations.create!(character:)
      conversation.messages.create!(role: "assistant", content: character.greeting)
      if persona_key == "returning"
        conversation.update!(summary: "Last week Nadia told #{character.first_name} she was starting a new job at a bakery and has a dog called Biscuit.")
        conversation.memories.create!(fact: "Started a new job at a bakery", importance: 3)
        conversation.memories.create!(fact: "Has a dog called Biscuit", importance: 2)
      end
      transcript = [ [ character.first_name, character.greeting ] ]

      @turns.times do
        said = user_turn(character, persona_key, transcript)
        conversation.messages.create!(role: "user", content: said)
        transcript << [ "User", said ]
        response = Llm.create(**ContextBuilder.new(conversation).params)
        reply = response.content.select { _1.type == :text }.map(&:text).join
        reply.split(SEPARATOR).map(&:strip).reject(&:empty?).each do |part|
          conversation.messages.create!(role: "assistant", content: part)
          transcript << [ character.first_name, part ]
        end
      end

      { character: character.slug, persona: persona_key, transcript:, critique: critique(character, persona_key, transcript) }
    ensure
      user&.destroy
    end

    def user_turn(character, persona_key, transcript)
      response = Llm.create(
        model: USER_MODEL, max_tokens: 1_000, output_config: { effort: "low" }, **Llm.thinking_for(USER_MODEL),
        system_: "You role-play a real person using a chat app, talking to #{character.name} (#{character.role}). You are: " \
                 "#{PERSONAS[persona_key]} Write only your next message, as that person would type it on a phone: " \
                 "natural, sometimes imperfect, in character, usually one or two sentences. Never mention that you are role-playing.",
        messages: [ { role: "user", content: "Conversation so far:\n#{format_transcript(transcript)}\n\nYour next message:" } ]
      )
      response.content.select { _1.type == :text }.map(&:text).join.strip.delete_prefix("User:").strip
    end

    def critique(character, persona_key, transcript)
      response = Llm.create(
        model: CRITIC, max_tokens: 6_000,
        output_config: { effort: "medium", format: { type: "json_schema", schema: CRITIQUE } },
        system_: "You are a demanding product reviewer for a consumer app where adults chat with AI characters. " \
                 "Read this conversation as the user would. Flag every reply that would confuse them (references to " \
                 "things never explained), ignores their level or needs, sounds like a generic assistant, is too long " \
                 "for a chat, or breaks the character. Character: #{character.name}, #{character.role}. #{character.persona.squish}",
        messages: [ { role: "user", content: "User persona: #{PERSONAS[persona_key]}\n\nTranscript:\n#{format_transcript(transcript)}" } ]
      )
      JSON.parse(response.content.find { _1.type == :text }.text)
    end

    def format_transcript(transcript) = transcript.map { |who, text| "#{who}: #{text}" }.join("\n")

    def write(results)
      dir = Rails.root.join("evals/simulations").tap(&:mkpath)
      stamp = Time.current.strftime("%Y-%m-%d-%H%M")
      File.write(dir.join("#{stamp}.json"), JSON.pretty_generate(results))
      axes = %w[makes_sense adapts human voice brevity]
      mean = ->(rows, axis) { (rows.sum { _1[:critique][axis] } / rows.size.to_f).round(1) }
      lines = [ "# Simulated conversations #{stamp}", "", "#{results.size} conversations, #{@turns} user turns each. Scores out of 5.", "",
                "| Character | #{axes.join(' | ')} |", "|---|#{'---|' * axes.size}" ]
      results.group_by { _1[:character] }.sort.each { |slug, rows| lines << "| #{slug} | #{axes.map { mean.(rows, _1) }.join(' | ')} |" }
      lines << "" << "## Issues" << ""
      results.sort_by { [ _1[:character], _1[:persona] ] }.each do |r|
        next if r[:critique]["issues"].empty?
        lines << "### #{r[:character]} × #{r[:persona]}" << "" << r[:critique]["verdict"] << ""
        r[:critique]["issues"].each { lines << "- turn #{_1['turn']}: “#{_1['quote'].to_s.first(160)}” — #{_1['problem']} **Fix:** #{_1['fix']}" }
        lines << ""
      end
      File.write(dir.join("#{stamp}.md"), lines.join("\n") + "\n")
      puts "Report: evals/simulations/#{stamp}.md"
    end
  end
end
