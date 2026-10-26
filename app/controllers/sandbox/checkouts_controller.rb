# The sandbox provider's hosted payment page: what Stripe or Upgate would show on their domain, here for the demo.
# The forms keep Rails' CSRF protection (they are ours); only the webhook endpoint is exempt.
class Sandbox::CheckoutsController < ApplicationController
  allow_unauthenticated_access
  before_action :require_sandbox, :load_state

  def show
    @product = Payments::Product.find(@state["product"])
  end

  def create
    outcome = params[:outcome]
    if outcome == "abandon"
      # leaving the page sends nothing: the Payment stays pending until reconciliation expires it
      redirect_to @state["cancel_url"], status: :see_other
    else
      Payments.provider.deliver(@state, outcome)
      redirect_to(outcome == "pay" ? @state["success_url"] : @state["cancel_url"], status: :see_other)
    end
  rescue Payments::InvalidSignature
    head :bad_request
  end

  private

  def require_sandbox = (head :not_found unless Payments.provider_name == "sandbox")

  def load_state
    @state = Payments::Providers::Sandbox.checkout_state(params[:token]) or head :gone
  end
end
