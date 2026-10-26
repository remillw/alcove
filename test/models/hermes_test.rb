require "test_helper"

class HermesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "a report tells Hermes without the message text" do
    ENV["HERMES_WEBHOOK_URL"], ENV["HERMES_WEBHOOK_SECRET"] = "http://hermes.test/webhooks/alcove", "s3cret"
    message = messages(:member_greeting)
    assert_enqueued_with(job: NotifyHermesJob) { Report.create!(message:, user: users(:member), kind: "user_flag") }
    body = enqueued_jobs.last[:args].last
    assert_no_match message.content, body
  ensure
    ENV.delete("HERMES_WEBHOOK_URL"); ENV.delete("HERMES_WEBHOOK_SECRET")
  end

  test "signs timestamp and body like Hermes expects" do
    ENV["HERMES_WEBHOOK_SECRET"] = "s3cret"
    request = Hermes.signed_request(URI("http://hermes.test/webhooks/alcove"), '{"a":1}', timestamp: "1700000000")
    assert_equal OpenSSL::HMAC.hexdigest("SHA256", "s3cret", '1700000000.{"a":1}'), request["X-Webhook-Signature-V2"]
    assert_equal "1700000000", request["X-Webhook-Timestamp"]
  ensure
    ENV.delete("HERMES_WEBHOOK_SECRET")
  end
end
