# "Cancel subscription" (create) and "Resume subscription" (destroy: taking the cancellation back). Both only ASK the
# provider; our mirror changes when its customer.subscription.updated comes back through the webhook, like every other
# state change. The provider asked is the one the subscription was bought with, not the currently configured one.
class Payments::CancellationsController < ApplicationController
  before_action :require_user
  before_action :load_subscription
  rate_limit to: 10, within: 1.minute, by: -> { Current.user&.id || request.remote_ip },
    with: -> { redirect_to account_path, alert: t("payments.checkouts.create.too_many") }

  def create
    return redirect_to(account_path, notice: t(".already"), status: :see_other) if @subscription.cancel_scheduled?

    provider.cancel_subscription(@subscription)
    redirect_to account_path, notice: t(".requested"), status: :see_other
  rescue Payments::Error => e
    unavailable(e)
  end

  # only while the period runs and a cancellation is pending; after the end it is a new subscription
  def destroy
    return redirect_to(account_path, alert: t(".too_late"), status: :see_other) unless @subscription.cancel_scheduled?

    provider.resume_subscription(@subscription)
    redirect_to account_path, notice: t(".resumed"), status: :see_other
  rescue Payments::Error => e
    unavailable(e)
  end

  private

  def load_subscription
    @subscription = current_user.active_subscription or redirect_to(account_path, alert: t("payments.cancellations.none"), status: :see_other)
  end

  def provider = Payments.provider(@subscription.provider)

  def unavailable(error)
    Rails.error.report(error)
    redirect_to account_path, alert: t(".unavailable"), status: :see_other
  end
end
