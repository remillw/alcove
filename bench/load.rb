# Load test for the reply pipeline, run inside a separate stack (compose project "alcove-bench", own database,
# LLM_FAKE=1 so a reply streams ~60 chunks over ~7 s like a real one, at no API cost):
#
#   docker compose -p alcove-bench ... exec jobs bin/rails runner bench/load.rb 300
#
# It creates N users who each send one message at the same moment, then measures what a user feels:
# queue wait (message saved -> job starts), time to first broadcast chunk, total reply time, and throughput.
n = Integer(ARGV.first || 100)
character = Character.published.first or abort "seed characters first"

users = Array.new(n) { User.create!(credit_balance: 0, adult_confirmed_at: Time.current).tap { Credits.post!(user: _1, amount: 5, kind: :grant, key: "bench:#{_1.id}") } }
conversations = users.map { _1.conversations.create!(character:) }
started = Time.current
replies = conversations.map { Turn.take!(conversation: _1, content: "Hello, bench!", nonce: SecureRandom.uuid).reply }
puts "#{n} messages accepted in #{(Time.current - started).round(2)} s"

ids = replies.map(&:id)
loop do
  done = Message.where(id: ids, status: %w[completed failed cancelled]).count
  print "\r#{done}/#{n} replies done"
  break if done == n || Time.current - started > 900
  sleep 1
end
elapsed = Time.current - started
puts

events = UsageEvent.where(message_id: ids, kind: "reply").pluck(:created_at, :latency_ms, :first_token_ms, :message_id)
wait = events.map { |created_at, latency, _, id| ((created_at - replies.find { _1.id == id }.created_at) * 1000 - latency).round }
pct = ->(xs, p) { xs.sort[(xs.size * p).ceil.clamp(1, xs.size) - 1] }
first = events.map(&:third).compact
puts "Throughput: #{(n / elapsed * 60).round} replies/min, all #{n} done in #{elapsed.round(1)} s"
puts "Queue wait ms: p50 #{pct.(wait, 0.5)}, p95 #{pct.(wait, 0.95)}"
puts "First token ms (in job): p50 #{pct.(first, 0.5)}, p95 #{pct.(first, 0.95)}"
puts "Failed: #{Message.where(id: ids, status: 'failed').count}"
User.where(id: users.map(&:id)).destroy_all
