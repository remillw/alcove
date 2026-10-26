require "test_helper"

class HermesTest < ActiveSupport::TestCase
  setup { ENV["HERMES_WEBHOOK_SECRET"] = "s3cret" }
  teardown { ENV.delete("HERMES_WEBHOOK_SECRET") }

  test "a report becomes a signed event for Hermes, without the message text" do
    message = messages(:member_greeting)
    Report.create!(message:, user: users(:member), kind: "user_flag")

    lines = Hermes.drain.map { JSON.parse(_1) }
    assert_equal 1, lines.size
    assert_no_match message.content, lines.first["body"]
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "s3cret", "#{lines.first['timestamp']}.#{lines.first['body']}"), lines.first["signature"]
    assert_empty Hermes.drain # drained once
  end

  test "nothing is queued when Hermes isn't configured" do
    ENV.delete("HERMES_WEBHOOK_SECRET")
    Report.create!(message: messages(:member_greeting), kind: "user_flag")
    assert_equal 0, OutboxEvent.count
  end
end
