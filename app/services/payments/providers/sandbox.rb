# A demonstration provider that lives inside the app. No money moves, and nothing here can be mistaken for a real
# payment: the hosted page (Sandbox::CheckoutsController) carries a loud "Test payment" banner.
#
# It behaves like a real provider, so the orchestration around it is the real one:
#   * checkout state lives with the "provider", not in our tables: a signed, expiring token carries it (like a
#     Stripe session id would), and our Payment only ever learns the outcome through a webhook;
#   * webhooks are signed `X-Sandbox-Signature: t=<unix>,v1=HMAC-SHA256(secret, "<t>.<body>")` and refused when the
#     timestamp is more than 5 minutes off (replay window);
#   * ids are derived from the checkout, so a double click or a replay sends the same event id and settles once.
#
# Delivery choice: the sandbox does not make an HTTP call to its own server (a thread of the same Puma waiting on
# itself, a public host to guess behind HAProxy, a live server in every test). It builds the exact signed request a
# provider would send and hands it to Payments::Webhooks.receive, the same code path as the real endpoint, signature
# check included. The only thing skipped is the network hop.
module Payments
  module Providers
    class Sandbox < Provider
      TTL = 1.hour
      TOLERANCE = 5.minutes
      HEADER = "X-Sandbox-Signature"

      # On the public site the sandbox is a demo of the flow, not a free-credit tap: one completed test purchase per
      # account (SANDBOX_DEMO_PURCHASES, default 1 in production, unlimited elsewhere). Real money goes through Stripe.
      def self.demo_limit = ENV.fetch("SANDBOX_DEMO_PURCHASES") { Rails.env.production? ? "1" : "" }.presence&.to_i

      def create_checkout(user:, product:, success_url:, cancel_url:, idempotency_key:)
        limit = self.class.demo_limit
        raise DemoLimit if limit && user.payments.where(provider: "sandbox", status: "paid").count >= limit

        state = { "reference" => idempotency_key, "product" => product.key, "amount_cents" => product.amount_cents,
                  "currency" => product.currency, "user_id" => user.id, "at" => Time.current.to_i,
                  "success_url" => success_url, "cancel_url" => cancel_url }
        token = self.class.verifier.generate(state, expires_in: TTL)
        Checkout.new(url: Rails.application.routes.url_helpers.sandbox_checkout_path(token), reference: checkout_id(idempotency_key))
      end

      def parse_webhook(request)
        verify_signature!(request.raw_post, request.headers[HEADER])
        body = JSON.parse(request.raw_post)
        data = body.fetch("data")
        type = { "payment.succeeded" => :payment_succeeded, "payment.failed" => :payment_failed,
                 "subscription.paid" => :subscription_paid }.fetch(body["type"], :ignored)
        Event.new(provider: name, id: body.fetch("id"), type:, token: data["reference"], external_id: data["payment_id"],
          subscription_id: data["subscription_id"], amount_cents: data["amount_cents"], currency: data["currency"],
          period_start: parse_time(data["period_start"]), period_end: parse_time(data["period_end"]))
      rescue JSON::ParserError, KeyError
        raise InvalidSignature, "malformed payload"
      end

      # The sandbox keeps no state: a checkout older than its token's life can no longer be completed.
      def fetch_event(payment)
        return if payment.created_at > TTL.ago
        Event.new(provider: name, id: "reconcile:#{payment.token}", type: :payment_expired, token: payment.token)
      end

      # ---- the "provider side" of the page: called by Sandbox::CheckoutsController -------------------------------

      def self.verifier = @verifier ||= ActiveSupport::MessageVerifier.new(
        Rails.application.key_generator.generate_key("payments sandbox checkout"), url_safe: true, serializer: JSON)

      def self.secret = Rails.application.key_generator.generate_key("payments sandbox webhook")

      # nil when the token is forged or expired
      def self.checkout_state(token) = verifier.verified(token.to_s)

      # Sends the signed webhook for what the customer did on the hosted page ("pay" or "decline").
      def deliver(state, outcome)
        reference = state.fetch("reference")
        payment_id = checkout_id(reference)
        data = { reference:, payment_id:, amount_cents: state["amount_cents"], currency: state["currency"] }
        type =
          if outcome == "decline" then "payment.failed"
          elsif Product.find(state["product"]).subscription?
            started = Time.at(state["at"]).utc
            data.merge!(subscription_id: "sbx_sub_#{payment_id.delete_prefix("sbx_")}", period_start: started.iso8601, period_end: (started + 1.month).iso8601)
            "subscription.paid"
          else "payment.succeeded"
          end
        id = "evt_#{payment_id}_#{outcome == "decline" ? "failed" : "paid"}"
        Webhooks.receive(self, signed_request({ id:, type:, created: Time.current.to_i, data: }.to_json))
      end

      private

      # opaque, stable per checkout, and not guessable from the Payment token
      def checkout_id(reference) = "sbx_#{OpenSSL::HMAC.hexdigest("SHA256", self.class.secret, "checkout:#{reference}")[0, 20]}"

      def signed_request(body, timestamp: Time.now.to_i)
        signature = OpenSSL::HMAC.hexdigest("SHA256", self.class.secret, "#{timestamp}.#{body}")
        env = Rack::MockRequest.env_for("/webhooks/sandbox", method: "POST", input: body, "CONTENT_TYPE" => "application/json",
          "HTTP_X_SANDBOX_SIGNATURE" => "t=#{timestamp},v1=#{signature}")
        ActionDispatch::Request.new(env)
      end

      def verify_signature!(body, header)
        parts = header.to_s.split(",").filter_map { _1.split("=", 2) if _1.include?("=") }.to_h
        timestamp = parts["t"].to_s
        raise InvalidSignature, "missing signature" if timestamp !~ /\A\d+\z/ || parts["v1"].blank?
        raise InvalidSignature, "timestamp outside the tolerance" if (Time.now.to_i - timestamp.to_i).abs > TOLERANCE.to_i
        expected = OpenSSL::HMAC.hexdigest("SHA256", self.class.secret, "#{timestamp}.#{body}")
        raise InvalidSignature, "signature mismatch" unless ActiveSupport::SecurityUtils.secure_compare(expected, parts["v1"])
      end

      def parse_time(value) = value && Time.iso8601(value).utc
    end
  end
end
