require "test_helper"

# the HTTP endpoint with the sandbox provider: signature, replay window, dedupe
class Payments::WebhooksTest < ActionDispatch::IntegrationTest
  include PaymentsTestHelper

  setup do
    @user = users(:member)
    @payment = create_payment
  end

  def post_webhook(body, **headers) = post("/webhooks/sandbox", params: body, headers: sandbox_headers(body).merge(headers))

  test "a valid signature is processed: payment paid, credits granted" do
    post_webhook sandbox_body(@payment)

    assert_response :ok
    assert @payment.reload.paid?
    assert_equal 55, @user.reload.credit_balance
    event = WebhookEvent.find_by!(provider: "sandbox", event_id: "evt_test_1")
    assert event.processed_at
    assert_equal @payment.token, event.payload.dig("data", "reference")
  end

  test "the same event delivered twice gives one credit and two 200s" do
    body = sandbox_body(@payment)
    2.times do
      post_webhook(body)
      assert_response :ok
    end

    assert_equal 55, @user.reload.credit_balance
    assert_equal 1, WebhookEvent.where(event_id: "evt_test_1").count
    assert_equal 1, CreditEntry.where(kind: "purchase").count
  end

  test "a wrong signature is refused and nothing is stored" do
    body = sandbox_body(@payment)
    post "/webhooks/sandbox", params: body, headers: sandbox_headers(body, secret: "not the secret")

    assert_response :bad_request
    assert_equal 0, WebhookEvent.count
    assert @payment.reload.pending?
  end

  test "a tampered body is refused" do
    body = sandbox_body(@payment)
    post "/webhooks/sandbox", params: body.sub("sbx_", "xxx_"), headers: sandbox_headers(body)
    assert_response :bad_request
    assert @payment.reload.pending?
  end

  test "a missing signature is refused" do
    post "/webhooks/sandbox", params: sandbox_body(@payment), headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :bad_request
  end

  test "a stale signature is refused (replay window of 5 minutes), a fresh one inside it passes" do
    body = sandbox_body(@payment)
    post "/webhooks/sandbox", params: body, headers: sandbox_headers(body, timestamp: 6.minutes.ago.to_i)
    assert_response :bad_request
    assert @payment.reload.pending?

    post "/webhooks/sandbox", params: body, headers: sandbox_headers(body, timestamp: 4.minutes.ago.to_i)
    assert_response :ok
    assert @payment.reload.paid?
  end

  test "an unknown or unconfigured provider is a 404" do
    post "/webhooks/nobody", params: "{}"
    assert_response :not_found
    post "/webhooks/stripe", params: "{}"
    assert_response :not_found
  end

  test "an event that fails halfway leaves no trace, so the provider's retry is processed" do
    body = sandbox_body(@payment)
    original = Payments::Settlement.method(:call)
    Payments::Settlement.define_singleton_method(:call) { |_event| raise "database hiccup" }
    begin
      assert_raises(RuntimeError) { post_webhook(body) }
    ensure
      Payments::Settlement.define_singleton_method(:call, original)
    end

    assert_equal 0, WebhookEvent.count
    post_webhook(body)
    assert_response :ok
    assert_equal 55, @user.reload.credit_balance
  end
end
