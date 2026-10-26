module PaymentsTestHelper
  def create_payment(user: users(:member), product: "pack_50", provider: "sandbox", **attrs)
    item = Payments::Product.find(product)
    user.payments.create!({ provider:, product_key: item.key, amount_cents: item.amount_cents, currency: item.currency, credits: item.credits }.merge(attrs))
  end

  def event(type, provider: "sandbox", id: SecureRandom.hex(6), **attrs) = Payments::Event.new(provider:, id:, type:, **attrs)

  def paid_event(payment, external_id: "pay_#{payment.id}", **attrs)
    event(:payment_succeeded, provider: payment.provider, token: payment.token, external_id:, amount_cents: payment.amount_cents, currency: payment.currency, **attrs)
  end

  def renewal_event(payment, period_start:, subscription_id: "sub_1", external_id: "in_#{period_start.to_i}", **attrs)
    event(:subscription_paid, provider: payment.provider, token: payment.token, subscription_id:, external_id:, amount_cents: 999, currency: "EUR",
      period_start:, period_end: period_start + 1.month, **attrs)
  end

  def with_env(**vars)
    old = vars.keys.to_h { [ _1, ENV[_1.to_s] ] }
    vars.each { |key, value| ENV[key.to_s] = value }
    yield
  ensure
    old.each { |key, value| ENV[key.to_s] = value }
  end

  # a body signed the way Payments::Providers::Sandbox signs: HMAC-SHA256 of "<t>.<body>"
  def sandbox_headers(body, timestamp: Time.now.to_i, secret: Payments::Providers::Sandbox.secret)
    { "X-Sandbox-Signature" => "t=#{timestamp},v1=#{OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{body}")}", "CONTENT_TYPE" => "application/json" }
  end

  def sandbox_body(payment, type: "payment.succeeded", id: "evt_test_1", **data)
    { id:, type:, created: Time.now.to_i, data: { reference: payment.token, payment_id: "sbx_#{payment.id}", amount_cents: payment.amount_cents, currency: payment.currency }.merge(data) }.to_json
  end

  STRIPE_SECRET = "whsec_test_secret"

  # a recorded Stripe event (test/fixtures/files/stripe), pointed at our payment, and signed like Stripe signs
  def stripe_fixture(name, token: "tok_unused", timestamp: Time.now)
    payload = file_fixture("stripe/#{name}.json").read.gsub("__TOKEN__", token)
    [ payload, { "Stripe-Signature" => "t=#{timestamp.to_i},v1=#{::Stripe::Webhook::Signature.compute_signature(timestamp, payload, STRIPE_SECRET)}", "CONTENT_TYPE" => "application/json" } ]
  end

  # stands in for ::Stripe::StripeClient: records what we send, answers what the test says
  class FakeStripeClient
    Session = Struct.new(:id, :url, :hash, keyword_init: true) { def to_hash = hash }
    attr_reader :created, :updated

    def initialize(retrieved: {}, failing: false) = (@retrieved = retrieved; @failing = failing)

    def v1 = self
    def checkout = self
    def sessions = self
    def subscriptions = self

    # subscriptions.update(id, params): records it, or fails like Stripe does when the subscription is gone
    def update(id, params, _opts = {})
      raise ::Stripe::InvalidRequestError.new("No such subscription: #{id}", "id") if @failing
      (@updated ||= []) << [ id, params ]
    end

    def create(params, opts)
      @created = [ params, opts ]
      Session.new(id: "cs_test_123", url: "https://checkout.stripe.com/c/pay/cs_test_123")
    end

    def retrieve(_id, _params = {}, _opts = {}) = Session.new(hash: @retrieved)
  end
end
