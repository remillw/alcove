class NotifyHermesJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :polynomially_longer, attempts: 5

  def perform(event_type, title, body) = Hermes.deliver(event_type, title, body)
end
