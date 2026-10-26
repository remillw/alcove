# Nightly: a webhook can be lost (our deploy, the provider's outage, a bug). Every payment still pending after an hour is
# put to the provider: paid -> caught up (same Settlement as a webhook, so the same credit key), expired -> closed.
# Still open or unknown after a day -> closed locally. Anything else waits for the next run.
class ReconcilePaymentsJob < ApplicationJob
  queue_as :default

  def perform
    Payment.stale.find_each do |payment|
      event = Payments.provider(payment.provider).fetch_event(payment)
      if event
        Payments::Settlement.call(event)
      elsif payment.created_at < 1.day.ago
        Payments::Settlement.call(Payments::Event.new(provider: payment.provider, id: "reconcile:#{payment.token}", type: :payment_expired, token: payment.token))
      end
    rescue Payments::Error => e
      Rails.error.report(e, context: { payment_id: payment.id }) # one provider down must not stop the others
    end
  end
end
