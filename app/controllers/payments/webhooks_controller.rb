# Provider notifications. No session, no CSRF token (a provider has neither): authenticity is the provider's signature,
# verified before anything else. 200 for processed and replayed events alike, so a provider stops retrying.
class Payments::WebhooksController < ApplicationController
  allow_unauthenticated_access
  skip_forgery_protection

  def create
    Payments::Webhooks.receive(Payments.provider(params[:provider]), request)
    head :ok
  rescue Payments::InvalidSignature
    head :bad_request
  rescue Payments::UnknownProvider, Payments::ProviderUnavailable
    head :not_found
  end
end
