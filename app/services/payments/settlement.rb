# Applies one normalised event to payments, subscriptions and the credits ledger. Safe to run twice with the same event:
# status changes are guarded, and every credit movement has an idempotency key, so a replay (or a reconciliation that
# races a webhook) can never pay twice. Called inside the webhook transaction, or alone by the reconciliation job.
module Payments
  module Settlement
    # money received beats any earlier verdict; a refunded payment stays refunded
    PAYABLE_FROM = %w[pending failed expired].freeze

    def self.call(event)
      case event.type
      when :payment_succeeded then payment_succeeded(event)
      when :payment_failed then close_pending(event, :failed)
      when :payment_expired then close_pending(event, :expired)
      when :payment_refunded then payment_refunded(event)
      when :subscription_paid then subscription_paid(event)
      when :subscription_past_due then subscription_past_due(event)
      when :subscription_updated then subscription_updated(event)
      when :subscription_canceled then subscription_canceled(event)
      end
    end

    def self.payment_succeeded(event)
      payment = Payment.find_by(provider: event.provider, token: event.token) or return unknown(event)
      payment.with_lock do
        next unless payment.status.in?(PAYABLE_FROM)

        if event.amount_cents != payment.amount_cents || event.currency != payment.currency
          # the provider charged something other than what we asked: no credits, a human looks
          payment.update!(status: :failed, metadata: payment.metadata.merge(mismatch: { amount_cents: event.amount_cents, currency: event.currency }))
          next Rails.error.report(Error.new("Payment #{payment.id}: provider charged #{event.amount_cents} #{event.currency}, expected #{payment.amount_cents} #{payment.currency}"))
        end

        payment.update!(status: :paid, external_id: event.external_id, paid_at: Time.current)
        Credits.post!(user: payment.user, amount: payment.credits, kind: :purchase,
          key: "payment:#{payment.provider}:#{payment.external_id}", metadata: { payment_id: payment.id, product: payment.product_key })
      end
    end

    # a first payment settles the pending Payment; a renewal gets a Payment row of its own (one per invoice)
    def self.subscription_paid(event)
      first = Payment.find_by(provider: event.provider, token: event.token) or return unknown(event)
      Payment.transaction do
        subscription = Subscription.find_or_initialize_by(provider: event.provider, external_id: event.subscription_id)
        subscription.lock! if subscription.persisted?
        subscription.assign_attributes(user: first.user, product_key: first.product_key)
        subscription.status = :active unless subscription.canceled?
        # an older event arriving late must not move the period backwards
        if subscription.current_period_start.nil? || event.period_start >= subscription.current_period_start
          subscription.assign_attributes(current_period_start: event.period_start, current_period_end: event.period_end)
        end
        subscription.save!

        payment = Payment.find_by(provider: event.provider, external_id: event.external_id)
        payment ||= first if first.status.in?(PAYABLE_FROM)
        payment ||= first.dup.tap { _1.token = nil }
        # a replayed invoice must not undo a refund: only a payment not yet settled becomes paid
        payment.update!(status: payment.settled? ? payment.status : :paid, external_id: event.external_id, subscription:, amount_cents: event.amount_cents,
          currency: event.currency, paid_at: payment.paid_at || Time.current)

        Credits.post!(user: first.user, amount: payment.credits, kind: :purchase,
          key: "subscription:#{subscription.id}:#{event.period_start.utc.iso8601}", metadata: { payment_id: payment.id, product: payment.product_key })
      end
    end

    # a failed renewal: past_due and no credits. A failed first payment has no subscription yet, so it fails the Payment.
    def self.subscription_past_due(event)
      if (subscription = Subscription.find_by(provider: event.provider, external_id: event.subscription_id))
        subscription.with_lock { subscription.past_due! unless subscription.canceled? }
      else
        close_pending(event, :failed)
      end
    end

    # the provider's view of "stop at the end of the period": scheduled or taken back. A canceled subscription is final.
    # An update about a subscription we haven't recorded yet is normal right after checkout (it can beat the first
    # invoice): nothing to mirror, so only a scheduled cancellation, which we should know about, is reported.
    def self.subscription_updated(event)
      subscription = Subscription.find_by(provider: event.provider, external_id: event.subscription_id)
      return (unknown(event) if event.cancel_at_period_end) unless subscription

      subscription.with_lock { subscription.update!(cancel_at_period_end: event.cancel_at_period_end == true) unless subscription.canceled? }
    end

    def self.subscription_canceled(event)
      subscription = Subscription.find_by(provider: event.provider, external_id: event.subscription_id) or return unknown(event)
      subscription.with_lock { subscription.update!(status: :canceled, canceled_at: Time.current) unless subscription.canceled? }
    end

    # Each refund is its own event (refund_id) and takes back the credits of the money it returned: the payment's credits
    # pro rata (Payment#credits_for, rounded half up on the cumulative total). Guarantees:
    #   * a refund seen twice (another event for the same refund, a replay) counts once: refund ids are kept on the
    #     payment and are also the ledger key;
    #   * refunds never add up to more than was charged, so never to more credits than were bought: an excess is cut
    #     to what is left and reported;
    #   * the balance never goes below zero (clamp): credits already spent are not recovered, the shortfall is written
    #     in the ledger entry. credits_refunded tracks the nominal credits so the pro rata stays exact regardless.
    # paid -> partially_refunded -> refunded (once everything is returned).
    def self.payment_refunded(event)
      payment = Payment.find_by(provider: event.provider, external_id: event.external_id) or return unknown(event)
      return unknown(event) if event.refund_id.blank? || event.amount_cents.to_i <= 0

      payment.with_lock do
        refunds = payment.metadata.fetch("refunds", {})
        next unless payment.settled? && !refunds.key?(event.refund_id)

        cents = [ event.amount_cents, payment.refundable_cents ].min
        if cents < event.amount_cents
          Rails.error.report(Error.new("Payment #{payment.id}: refund #{event.refund_id} of #{event.amount_cents} exceeds the #{payment.refundable_cents} left, counted as #{cents}"))
        end
        next if cents.zero?

        refunded = payment.refunded_cents + cents
        credits = payment.credits_for(refunded)
        owed = credits - payment.credits_refunded # what this refund adds, 0 when it is too small to be worth a credit
        payment.update!(refunded_cents: refunded, credits_refunded: credits, status: refunded == payment.amount_cents ? :refunded : :partially_refunded,
          metadata: payment.metadata.merge("refunds" => refunds.merge(event.refund_id => cents)))

        Credits.post!(user: payment.user, amount: -owed, kind: :adjustment, clamp: true,
          key: "refund:#{payment.provider}:#{event.refund_id}", metadata: { reason: "refund", payment_id: payment.id, refund_cents: cents }) if owed.positive?
      end
    end

    def self.close_pending(event, status)
      payment = Payment.find_by(provider: event.provider, token: event.token) or return unknown(event)
      payment.with_lock { payment.update!(status:) if payment.pending? }
    end

    # a reference we never issued: acknowledged (the provider must not retry forever) but reported
    def self.unknown(event)
      Rails.error.report(Error.new("#{event.provider} event #{event.id} (#{event.type}) matches nothing we know"))
      nil
    end
  end
end
