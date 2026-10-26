# Hermes is Rémi's operations agent on the same server. Alcove tells it what a human should look at (reports,
# distress) and a daily digest. Only counts and ids, never the text of a conversation.
#
# Hermes listens on the server's loopback only (firewall), so the container doesn't call it: events go to an outbox
# table, and bin/hermes-relay (cron on the host, every minute) drains them as signed requests and posts them locally.
# Signature: hex HMAC-SHA256 of "<timestamp>.<body>" (X-Webhook-Signature-V2 + X-Webhook-Timestamp).
module Hermes
  def self.enabled? = ENV["HERMES_WEBHOOK_SECRET"].present?

  def self.notify(event_type, title:, body:)
    OutboxEvent.create!(event_type:, payload: { event_type:, title:, body: }.to_json) if enabled?
  end

  # one line of JSON per event, ready to post; the rows are removed in the same transaction
  def self.drain(limit: 50)
    OutboxEvent.transaction do
      events = OutboxEvent.order(:id).limit(limit).lock("FOR UPDATE SKIP LOCKED").to_a
      OutboxEvent.where(id: events.map(&:id)).delete_all
      events.map { |event| signed(event.payload).merge(id: event.id).to_json }
    end
  end

  def self.signed(payload, timestamp: Time.now.to_i.to_s)
    { body: payload, timestamp:, signature: OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("HERMES_WEBHOOK_SECRET"), "#{timestamp}.#{payload}") }
  end
end
