# "Buy" and "Subscribe": records a pending Payment from the catalogue, then sends the customer to the provider.
class Payments::CheckoutsController < ApplicationController
  rate_limit to: 10, within: 1.minute, by: -> { Current.user&.id || request.remote_ip }, only: :create,
    with: -> { redirect_to account_path, alert: t("payments.checkouts.create.too_many") }
  before_action :require_user

  def create
    return redirect_to(new_registration_path, notice: t(".sign_up_first")) if current_user.guest?

    product = Payments::Product.find(params[:product]) # only the key comes from the browser
    provider = Payments.provider
    payment = current_user.payments.create!(provider: provider.name, product_key: product.key, amount_cents: product.amount_cents,
      currency: product.currency, credits: product.credits)

    checkout = provider.create_checkout(user: current_user, product:, idempotency_key: payment.token,
      success_url: account_url(checkout: "success"), cancel_url: account_url(checkout: "cancelled"))
    payment.update!(checkout_ref: checkout.reference)
    redirect_to checkout.url, allow_other_host: true, status: :see_other
  rescue Payments::UnknownProduct
    head :unprocessable_entity
  rescue Payments::DemoLimit
    payment&.failed!
    redirect_to account_path, alert: t(".demo_limit")
  rescue Payments::Error => e
    payment&.failed!
    Rails.error.report(e)
    redirect_to account_path, alert: t(".unavailable")
  end
end
