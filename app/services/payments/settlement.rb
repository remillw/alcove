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
        payment.update!(status: :paid, external_id: event.external_id, subscription:, amount_cents: event.amount_cents,
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

    def self.subscription_canceled(event)
      subscription = Subscription.find_by(provider: event.provider, external_id: event.subscription_id) or return unknown(event)
      subscription.with_lock { subscription.update!(status: :canceled, canceled_at: Time.current) unless subscription.canceled? }
    end

    # only a full refund takes the credits back (partial refunds are left to a human)
    def self.payment_refunded(event)
      payment = Payment.find_by(provider: event.provider, external_id: event.external_id) or return unknown(event)
      payment.with_lock do
        next unless payment.paid? && event.amount_cents >= payment.amount_cents

        payment.refunded!
        # clamp: credits already spent can't be clawed back below zero; what is missing is recorded in the entry
        Credits.post!(user: payment.user, amount: -payment.credits, kind: :adjustment, clamp: true,
          key: "refund:#{payment.provider}:#{payment.external_id}", metadata: { reason: "refund", payment_id: payment.id })
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
