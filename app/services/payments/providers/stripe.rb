# Stripe through its official gem: hosted Checkout Sessions (mode payment for packs, mode subscription for the plan)
# and signature-verified webhooks. Active only when STRIPE_SECRET_KEY and STRIPE_WEBHOOK_SECRET are both set.
#
# Inside this namespace `Stripe` is this class, so the gem is always written ::Stripe.
module Payments
  module Providers
    class Stripe < Provider
      SESSION_LIFETIME = 30.minutes # Stripe's minimum; an abandoned session is then expired by Stripe itself

      def self.enabled? = ENV["STRIPE_SECRET_KEY"].present? && ENV["STRIPE_WEBHOOK_SECRET"].present?

      # client: anything shaped like ::Stripe::StripeClient (the tests pass a recording fake, so no network)
      def initialize(client: nil, webhook_secret: ENV["STRIPE_WEBHOOK_SECRET"])
        @client = client || ::Stripe::StripeClient.new(ENV.fetch("STRIPE_SECRET_KEY"))
        @webhook_secret = webhook_secret
      end

      def create_checkout(user:, product:, success_url:, cancel_url:, idempotency_key:)
        metadata = { payment_token: idempotency_key }
        price = { currency: product.currency.downcase, unit_amount: product.amount_cents, product_data: { name: "Alcove: #{product.name}" } }
        params = { mode: product.subscription? ? "subscription" : "payment", success_url:, cancel_url:,
                   client_reference_id: idempotency_key, metadata:, expires_at: SESSION_LIFETIME.from_now.to_i,
                   line_items: [ { quantity: 1, price_data: price } ] }
        params[:customer_email] = user.email_address if user.email_address.present?
        if product.subscription?
          price[:recurring] = { interval: "month" }
          params[:subscription_data] = { metadata: } # echoed on every invoice: how a renewal finds its user
        else
          params[:payment_intent_data] = { metadata: } # and on the charge: how a refund finds its payment
        end

        session = @client.v1.checkout.sessions.create(params, { idempotency_key: })
        Checkout.new(url: session.url, reference: session.id)
      rescue ::Stripe::StripeError => e
        raise Error, "Stripe refused the checkout: #{e.message}"
      end

      def parse_webhook(request)
        event = verified_event(request)
        normalise(event.id, event.type, event.data.object.to_hash)
      end

      def fetch_event(payment)
        return if payment.checkout_ref.blank?
        session = @client.v1.checkout.sessions.retrieve(payment.checkout_ref, { expand: [ "invoice" ] }).to_hash
        id = "reconcile:#{payment.token}"
        case session[:status]
        when "expired" then Event.new(provider: name, id:, type: :payment_expired, token: payment.token)
        when "complete" then session[:mode] == "subscription" ? invoice_event(id, session[:invoice]) : session_event(id, session)
        end
      end

      private

      def verified_event(request)
        ::Stripe::Webhook.construct_event(request.raw_post, request.headers["Stripe-Signature"], @webhook_secret) # default tolerance: 5 minutes
      rescue ::Stripe::SignatureVerificationError, JSON::ParserError, ArgumentError => e
        raise InvalidSignature, e.message
      end

      def normalise(id, type, object)
        case type
        when "checkout.session.completed", "checkout.session.async_payment_succeeded"
          session_event(id, object) if object[:mode] == "payment"
        when "checkout.session.async_payment_failed"
          Event.new(provider: name, id:, type: :payment_failed, token: object[:client_reference_id])
        when "checkout.session.expired"
          Event.new(provider: name, id:, type: :payment_expired, token: object[:client_reference_id])
        when "charge.refunded"
          Event.new(provider: name, id:, type: :payment_refunded, external_id: object[:payment_intent], amount_cents: object[:amount_refunded], currency: object[:currency]&.upcase)
        when "invoice.paid"
          invoice_event(id, object)
        when "invoice.payment_failed"
          subscription_id, metadata = subscription_of(object)
          Event.new(provider: name, id:, type: :subscription_past_due, subscription_id:, token: metadata[:payment_token]) if subscription_id
        when "customer.subscription.deleted"
          Event.new(provider: name, id:, type: :subscription_canceled, subscription_id: object[:id])
        end || Event.new(provider: name, id:, type: :ignored)
      end

      # a Checkout Session in payment mode; "unpaid" means a delayed method (the async_* events follow)
      def session_event(id, session)
        return unless session[:payment_status] == "paid"
        Event.new(provider: name, id:, type: :payment_succeeded, token: session[:client_reference_id], external_id: session[:payment_intent],
          amount_cents: session[:amount_total], currency: session[:currency]&.upcase)
      end

      def invoice_event(id, invoice)
        subscription_id, metadata = subscription_of(invoice)
        return unless subscription_id && invoice[:amount_paid].to_i.positive?
        period = invoice.dig(:lines, :data, 0, :period)
        Event.new(provider: name, id:, type: :subscription_paid, token: metadata[:payment_token], external_id: invoice[:id], subscription_id:,
          amount_cents: invoice[:amount_paid], currency: invoice[:currency].upcase,
          period_start: Time.at(period[:start]).utc, period_end: Time.at(period[:end]).utc)
      end

      # the API moved these under `parent.subscription_details` in 2025; older versions have them on the invoice
      def subscription_of(invoice)
        details = invoice.dig(:parent, :subscription_details) || invoice[:subscription_details] || {}
        [ details[:subscription] || invoice[:subscription], details[:metadata] || {} ]
      end
    end
  end
end
