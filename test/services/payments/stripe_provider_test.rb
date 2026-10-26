require "test_helper"

# Stripe, with recorded events signed in the test and a fake client: no network, no keys.
class Payments::StripeProviderTest < ActionDispatch::IntegrationTest
  include PaymentsTestHelper

  setup do
    @user = users(:member)
    @client = FakeStripeClient.new
    @provider = Payments::Providers::Stripe.new(client: @client, webhook_secret: STRIPE_SECRET)
  end

  def parse(name, token: "tok", **options)
    payload, headers = stripe_fixture(name, token:, **options)
    @provider.parse_webhook(ActionDispatch::Request.new(Rack::MockRequest.env_for("/webhooks/stripe", method: "POST", input: payload, **headers.transform_keys { "HTTP_#{_1.upcase.tr("-", "_")}" })))
  end

  test "only active when both keys are present" do
    with_env(STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: nil) { assert_not Payments::Providers::Stripe.enabled? }
    with_env(STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: nil) { assert_not Payments::Providers::Stripe.enabled? }
    with_env(STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: "whsec_x") { assert Payments::Providers::Stripe.enabled? }
    with_env(STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: nil) { assert_raises(Payments::ProviderUnavailable) { Payments::Registry.fetch("stripe") } }
  end

  test "a pack is a Checkout Session in payment mode, priced from the catalogue, idempotent on our token" do
    checkout = @provider.create_checkout(user: @user, product: Payments::Product.find("pack_150"), success_url: "https://a.test/ok", cancel_url: "https://a.test/no", idempotency_key: "tok-1")
    params, options = @client.created

    assert_equal "https://checkout.stripe.com/c/pay/cs_test_123", checkout.url
    assert_equal "cs_test_123", checkout.reference
    assert_equal "payment", params[:mode]
    assert_equal({ currency: "eur", unit_amount: 1199 }, params[:line_items][0][:price_data].slice(:currency, :unit_amount))
    assert_equal "tok-1", params[:client_reference_id]
    assert_equal({ payment_token: "tok-1" }, params[:payment_intent_data][:metadata])
    assert_equal({ idempotency_key: "tok-1" }, options)
    assert_equal @user.email_address, params[:customer_email]
  end

  test "the plan is a Checkout Session in subscription mode, monthly, carrying our token on the subscription" do
    @provider.create_checkout(user: @user, product: Payments::Product.subscription, success_url: "https://a.test/ok", cancel_url: "https://a.test/no", idempotency_key: "tok-2")
    params, = @client.created

    assert_equal "subscription", params[:mode]
    assert_equal({ interval: "month" }, params[:line_items][0][:price_data][:recurring])
    assert_equal 999, params[:line_items][0][:price_data][:unit_amount]
    assert_equal({ payment_token: "tok-2" }, params[:subscription_data][:metadata])
  end

  test "checkout.session.completed becomes payment_succeeded" do
    event = parse(:checkout_session_completed, token: "tok-3")
    assert_equal [ :payment_succeeded, "evt_1CheckoutCompleted", "tok-3", "pi_3Abc", 499, "EUR" ],
      event.to_h.values_at(:type, :id, :token, :external_id, :amount_cents, :currency)
  end

  test "the other events are normalised too" do
    assert_equal :payment_expired, parse(:checkout_session_expired, token: "tok").type
    refund = parse(:refund_created)
    assert_equal [ :payment_refunded, "pi_3Abc", "re_3Abc", 499, "EUR" ], refund.to_h.values_at(:type, :external_id, :refund_id, :amount_cents, :currency)
    assert_equal 100, parse(:refund_partial).amount_cents
    assert_equal :ignored, parse(:refund_pending).type # no money has moved yet
    assert_equal :ignored, parse(:charge_refunded).type # a running total with no refund id: refund.* carry the countable one
    invoice = parse(:invoice_paid, token: "tok-4")
    assert_equal [ :subscription_paid, "sub_1Abc", "in_1Abc", "tok-4", 999 ], invoice.to_h.values_at(:type, :subscription_id, :external_id, :token, :amount_cents)
    assert_equal [ Time.at(1793000000).utc, Time.at(1795592000).utc ], [ invoice.period_start, invoice.period_end ]
    assert_equal [ :subscription_past_due, "sub_1Abc" ], parse(:invoice_payment_failed).to_h.values_at(:type, :subscription_id)
    assert_equal [ :subscription_canceled, "sub_1Abc" ], parse(:customer_subscription_deleted).to_h.values_at(:type, :subscription_id)
    assert_equal [ :subscription_updated, "sub_1Abc", true ], parse(:customer_subscription_cancel_scheduled).to_h.values_at(:type, :subscription_id, :cancel_at_period_end)
    assert_equal [ :subscription_updated, false ], parse(:customer_subscription_resumed).to_h.values_at(:type, :cancel_at_period_end)
    assert_equal :ignored, parse(:customer_created).type
  end

  test "a wrong secret, a missing header and a stale timestamp are all refused" do
    payload, headers = stripe_fixture(:checkout_session_completed)
    request = ->(h) { ActionDispatch::Request.new(Rack::MockRequest.env_for("/webhooks/stripe", method: "POST", input: payload, **h)) }
    forged = Payments::Providers::Stripe.new(client: @client, webhook_secret: "whsec_other")

    assert_raises(Payments::InvalidSignature) { forged.parse_webhook(request.call("HTTP_STRIPE_SIGNATURE" => headers["Stripe-Signature"])) }
    assert_raises(Payments::InvalidSignature) { @provider.parse_webhook(request.call({})) }
    assert_raises(Payments::InvalidSignature) { parse(:checkout_session_completed, timestamp: 10.minutes.ago) }
  end

  # ---- end to end through the HTTP endpoint ---------------------------------------------------------------------

  test "POST /webhooks/stripe: a signed recorded event pays the payment, a replay changes nothing" do
    payment = create_payment(provider: "stripe")
    payload, headers = stripe_fixture(:checkout_session_completed, token: payment.token)

    with_env(STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: STRIPE_SECRET) do
      2.times do
        post "/webhooks/stripe", params: payload, headers: headers
        assert_response :ok
      end
    end

    assert payment.reload.paid?
    assert_equal "pi_3Abc", payment.external_id
    assert_equal 55, @user.reload.credit_balance
    assert_equal 1, WebhookEvent.where(provider: "stripe").count
  end

  test "POST /webhooks/stripe: a bad signature is a 400 and changes nothing" do
    payment = create_payment(provider: "stripe")
    payload, headers = stripe_fixture(:checkout_session_completed, token: payment.token)

    with_env(STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: "whsec_wrong") do
      post "/webhooks/stripe", params: payload, headers: headers
    end

    assert_response :bad_request
    assert payment.reload.pending?
    assert_equal 0, WebhookEvent.count
  end

  test "a renewal, a failed renewal and a refund, in order, through the endpoint" do
    first = create_payment(provider: "stripe", product: "regular")
    pack = create_payment(provider: "stripe", external_id: "pi_3Abc", status: "paid", paid_at: Time.current)
    Credits.post!(user: @user, amount: 50, kind: :purchase, key: "payment:stripe:pi_3Abc")

    with_env(STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: STRIPE_SECRET) do
      [ [ :invoice_paid, first.token ], [ :invoice_payment_failed, first.token ], [ :refund_created, "-" ] ].each do |name, token|
        payload, headers = stripe_fixture(name, token:)
        post "/webhooks/stripe", params: payload, headers: headers
        assert_response :ok
      end
    end

    subscription = Subscription.find_by!(provider: "stripe", external_id: "sub_1Abc")
    assert subscription.past_due?
    assert pack.reload.refunded?
    assert_equal 305, @user.reload.credit_balance # 5 + 50 pack - 50 refund + 300 month
  end

  # ---- cancellation and resume -----------------------------------------------------------------------------------

  def stripe_subscription(**attrs)
    Subscription.create!({ user: @user, provider: "stripe", external_id: "sub_1Abc", product_key: "regular", current_period_start: 5.days.ago, current_period_end: 25.days.from_now }.merge(attrs))
  end

  def post_stripe(name, token: "-")
    payload, headers = stripe_fixture(name, token:)
    with_env(STRIPE_SECRET_KEY: "sk_test_x", STRIPE_WEBHOOK_SECRET: STRIPE_SECRET) { post "/webhooks/stripe", params: payload, headers: headers }
    assert_response :ok
  end

  test "cancelling asks Stripe to stop at the period's end, not now" do
    @provider.cancel_subscription(stripe_subscription)
    assert_equal [ [ "sub_1Abc", { cancel_at_period_end: true } ] ], @client.updated
  end

  test "resuming sets the flag back" do
    @provider.resume_subscription(stripe_subscription)
    assert_equal [ [ "sub_1Abc", { cancel_at_period_end: false } ] ], @client.updated
  end

  test "a Stripe refusal becomes a Payments::Error and nothing is assumed" do
    provider = Payments::Providers::Stripe.new(client: FakeStripeClient.new(failing: true), webhook_secret: STRIPE_SECRET)
    assert_raises(Payments::Error) { provider.cancel_subscription(stripe_subscription) }
  end

  test "recorded events end to end: scheduled, replayed, resumed, scheduled again, then deleted" do
    subscription = stripe_subscription

    2.times { post_stripe(:customer_subscription_cancel_scheduled) }
    assert subscription.reload.cancel_scheduled?
    assert_equal 1, WebhookEvent.where(event_id: "evt_1SubCancel").count

    post_stripe(:customer_subscription_resumed)
    assert_not subscription.reload.cancel_scheduled?

    post_stripe(:customer_subscription_cancel_scheduled) # a new event id would be a new action; the fixture's id is a replay
    assert_not subscription.reload.cancel_scheduled?, "the replayed event was not applied twice"

    post_stripe(:customer_subscription_deleted)
    assert subscription.reload.canceled?
    assert_nil @user.active_subscription
  end

  # ---- partial refunds -------------------------------------------------------------------------------------------

  test "recorded refund events: two partial refunds, a pending one that changes nothing, a replay" do
    pack = create_payment(provider: "stripe", external_id: "pi_3Abc", status: "paid", paid_at: Time.current)
    Credits.post!(user: @user, amount: 50, kind: :purchase, key: "payment:stripe:pi_3Abc") # 55

    post_stripe(:refund_pending)
    assert pack.reload.paid?

    2.times { post_stripe(:refund_partial) } # 100 cents -> 10 credits, once
    assert pack.reload.partially_refunded?
    assert_equal 45, @user.reload.credit_balance

    post_stripe(:refund_created) # 499 cents on top of the 100: only 399 are left to return
    assert pack.reload.refunded?
    assert_equal [ 499, 50 ], pack.values_at(:refunded_cents, :credits_refunded)
    assert_equal 5, @user.reload.credit_balance
  end

  # ---- reconciliation ------------------------------------------------------------------------------------------

  test "reconciliation asks Stripe about the stored session: complete and paid is caught up" do
    payment = create_payment(provider: "stripe", checkout_ref: "cs_test_a1b2c3")
    @client = FakeStripeClient.new(retrieved: { status: "complete", mode: "payment", payment_status: "paid", client_reference_id: payment.token,
                                                payment_intent: "pi_late", amount_total: 499, currency: "eur" })
    provider = Payments::Providers::Stripe.new(client: @client, webhook_secret: STRIPE_SECRET)

    assert_equal [ :payment_succeeded, "pi_late" ], provider.fetch_event(payment).to_h.values_at(:type, :external_id)
  end

  test "reconciliation: an expired session is expired, an open one is left alone" do
    payment = create_payment(provider: "stripe", checkout_ref: "cs_test_a1b2c3")
    expired = Payments::Providers::Stripe.new(client: FakeStripeClient.new(retrieved: { status: "expired" }), webhook_secret: STRIPE_SECRET)
    open = Payments::Providers::Stripe.new(client: FakeStripeClient.new(retrieved: { status: "open" }), webhook_secret: STRIPE_SECRET)

    assert_equal :payment_expired, expired.fetch_event(payment).type
    assert_nil open.fetch_event(payment)
  end
end
