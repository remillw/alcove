# The one entry point for a provider's notification, used by the HTTP endpoint (and by the sandbox, which delivers its
# own webhooks through here). Order matters: signature first, then dedupe, then effects, all in one transaction.
module Payments
  module Webhooks
    # :processed or :duplicate; raises Payments::InvalidSignature before anything is read or written
    def self.receive(provider, request)
      event = provider.parse_webhook(request)

      WebhookEvent.transaction do
        # insert-or-ignore on the unique index: a concurrent delivery of the same event waits here, then skips
        inserted = WebhookEvent.insert({ provider: provider.name, event_id: event.id, event_type: event.type.to_s,
          payload: JSON.parse(request.raw_post) }, unique_by: %i[provider event_id], returning: %w[id])
        next :duplicate if inserted.rows.empty?

        Settlement.call(event)
        WebhookEvent.where(id: inserted.rows.first.first).update_all(processed_at: Time.current)
        :processed
      end
    end
  end
end
