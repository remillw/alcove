# Hermes is Rémi's operations agent on the same server. Alcove tells it what a human should look at (reports,
# distress) and a daily digest, as signed webhooks (HMAC-SHA256 of "<timestamp>.<body>"). Only counts and ids:
# never the text of a conversation.
module Hermes
  def self.enabled? = ENV["HERMES_WEBHOOK_URL"].present? && ENV["HERMES_WEBHOOK_SECRET"].present?

  def self.notify(event_type, title:, body:)
    NotifyHermesJob.perform_later(event_type, title, body) if enabled?
  end

  def self.deliver(event_type, title, body)
    uri = URI(ENV.fetch("HERMES_WEBHOOK_URL"))
    request = signed_request(uri, { event_type:, title:, body: }.to_json)
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 3, read_timeout: 10) { _1.request(request) }
    raise "Hermes webhook #{response.code}" unless response.is_a?(Net::HTTPSuccess)
  end

  def self.signed_request(uri, payload, timestamp: Time.now.to_i.to_s)
    signature = OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("HERMES_WEBHOOK_SECRET"), "#{timestamp}.#{payload}")
    Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "X-Webhook-Timestamp" => timestamp,
      "X-Webhook-Signature-V2" => signature, "X-Request-ID" => SecureRandom.uuid).tap { _1.body = payload }
  end
end
