require "test_helper"

class RecallTest < ActiveSupport::TestCase
  setup do
    @conversation = conversations(:member_june)
    # 7 important facts (3 beat 2), then facts nobody would list first
    7.times { |i| @conversation.memories.create!(fact: "Core fact number #{i}", importance: 3) }
    @dog = @conversation.memories.create!(fact: "Has a dog called Biscuit", importance: 1)
    @tea = @conversation.memories.create!(fact: "Drinks green tea every morning", importance: 1)
    @conversation.messages.create!(role: "user", content: "Biscuit chewed my slippers again")
  end

  test "full text brings back the fact the message is about, the other conversations' facts stay out" do
    conversations(:guest_june).memories.create!(fact: "Biscuit is also a cat elsewhere", importance: 1)

    found = Recall.new(@conversation, engine: :fulltext).relevant("Biscuit chewed my slippers")

    assert_equal [ "Has a dog called Biscuit" ], found.map(&:fact)
  end

  test "French and English words match, plurals and prefixes included" do
    @conversation.memories.create!(fact: "Adore les voyages en train", importance: 1)
    assert_includes Recall.new(@conversation, engine: :fulltext).relevant("un voyage demain").map(&:fact), "Adore les voyages en train"
  end

  test "merge rule: 5 most important first, then relevant ones, no duplicates" do
    @conversation.memories.create!(fact: "Core fact about Biscuit", importance: 3) # important AND relevant: listed once

    facts = Recall.new(@conversation, engine: :fulltext).facts

    assert_equal Recall::IMPORTANT, facts.first(Recall::IMPORTANT).count { _1.start_with?("Core fact") }
    assert_equal facts.uniq, facts
    assert_includes facts, "Has a dog called Biscuit"
    assert_not_includes facts, "Drinks green tea every morning"
    assert_operator facts.size, :<=, Recall::IMPORTANT + Recall::RELEVANT
  end

  test "a message with nothing in common still gets the important facts" do
    assert_equal Recall::IMPORTANT, Recall.new(@conversation, engine: :fulltext).facts("zzz").size
  end

  test "without a key the engine is full text; with one it is embeddings" do
    without_voyage { assert_equal :fulltext, Recall.engine }
    with_voyage { assert_equal :embeddings, Recall.engine }
  end

  test "embeddings engine finds the nearest fact by meaning, with no word in common" do
    with_voyage(vectors: { "Has a dog called Biscuit" => 3, "Drinks green tea every morning" => 4, "Time for his walk?" => 3 }) do
      [ @dog, @tea ].each { EmbedMemoryJob.perform_now(_1) }

      found = Recall.new(@conversation, engine: :embeddings).relevant("Time for his walk?", limit: 1)

      assert_equal [ @dog ], found
      assert_equal "query", @voyage_calls.last.payload[:input_type]
    end
  end

  test "if Voyage fails the reply still gets full-text results" do
    with_voyage(status: 500) do
      assert_equal [ "Has a dog called Biscuit" ], Recall.new(@conversation, engine: :embeddings).relevant("Biscuit chewed my slippers").map(&:fact)
    end
  end

  test "the prompt's memory block carries the relevant fact even when it is not among the most important" do
    system = ContextBuilder.new(@conversation).params[:system_]
    memory = system.last[:text]

    assert_includes memory, "- Has a dog called Biscuit"
    assert_not_includes memory, "Drinks green tea"
  end
end
