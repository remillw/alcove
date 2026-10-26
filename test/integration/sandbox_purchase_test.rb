require "test_helper"

class RefusingProvider < Payments::Provider
  def create_checkout(**) = raise(Payments::Error, "provider is down")
end

# The whole journey with the sandbox provider: buy -> hosted test page -> signed webhook -> credits.
class SandboxPurchaseTest < ActionDispatch::IntegrationTest
  include PaymentsTestHelper

  setup do
    @user = users(:member) # 5 credits
    sign_in_as @user
  end

  def start_checkout(product)
    post checkouts_path, params: { product: }
    assert_response :see_other
    assert_match %r{\A/sandbox/checkout/}, response.location.delete_prefix("http://www.example.com")
    URI(response.location).path
  end

  test "buying a pack: checkout page with the test banner, Pay (test), webhook, credits" do
    path = start_checkout("pack_50")
    payment = @user.payments.last
    assert payment.pending?
    assert_equal [ "sandbox", "pack_50", 499, 50 ], payment.values_at(:provider, :product_key, :amount_cents, :credits)

    get path
    assert_response :success
    assert_select ".test-banner", /Test payment, no real money/
    assert_select "button", "Pay (test)"
    assert_select "button", "Decline (test)"
    assert_select "button", "Abandon"
    assert_equal 5, @user.reload.credit_balance # nothing before the webhook

    post "#{path}/pay"
    assert_redirected_to account_url(checkout: "success")
    assert payment.reload.paid?
    assert_equal 55, @user.reload.credit_balance
    assert_equal "payment:sandbox:#{payment.external_id}", CreditEntry.order(:id).last.idempotency_key
    assert WebhookEvent.find_by!(provider: "sandbox").processed_at

    follow_redirect!
    assert_select ".flash", /Your credits will appear/
    assert_select ".balance", "55"
  end

  test "paying twice on the same page credits once" do
    path = start_checkout("pack_150")
    2.times { post "#{path}/pay" }

    assert_equal 155, @user.reload.credit_balance
    assert_equal 1, WebhookEvent.count
  end

  test "Decline (test) fails the payment, and a later Pay can't be undone by a decline" do
    path = start_checkout("pack_50")
    post "#{path}/decline"
    assert_redirected_to account_url(checkout: "cancelled")
    assert @user.payments.last.failed?
    assert_equal 5, @user.reload.credit_balance

    post "#{path}/pay" # back button, second try: the money wins
    assert @user.payments.last.paid?
    post "#{path}/decline"
    assert @user.payments.last.paid?
    assert_equal 55, @user.reload.credit_balance
  end

  test "Abandon sends nothing: the payment stays pending until reconciliation" do
    path = start_checkout("pack_50")
    post "#{path}/abandon"

    assert_redirected_to account_url(checkout: "cancelled")
    assert @user.payments.last.pending?
    assert_equal 0, WebhookEvent.count
  end

  test "subscribing grants the plan's credits and shows the subscription on the account page" do
    path = start_checkout("regular")
    post "#{path}/pay"

    subscription = @user.subscriptions.sole
    assert subscription.active?
    assert subscription.current_period_end > 25.days.from_now
    assert_equal 305, @user.reload.credit_balance
    assert_equal 1, CreditEntry.where("idempotency_key LIKE ?", "subscription:#{subscription.id}:%").count

    get account_path
    assert_select "p.muted", /Regular subscription is active until/
    assert_select "button", text: "Subscribe", count: 0
    assert_select "button", text: "Buy", count: 2
  end

  test "the account page offers both packs and the subscription" do
    get account_path
    assert_select "button", text: "Buy", count: 2
    assert_select "button", "Subscribe"
    assert_select "li.list__item", /€4\.99/
    assert_select "li.list__item", /€11\.99/
    assert_select "li.list__item", /€9\.99 \/ month/
  end

  test "French copy and price format" do
    # the ledger table uses l(time, format: :short), which core French date formats (not ours) provide
    I18n.backend.store_translations(:fr, time: { formats: { short: "%d/%m %H:%M" } })
    I18n.with_locale(:fr) do
      get account_path
      assert_select "li.list__item", /4,99 €/
      assert_select "button", text: "Acheter", count: 2
      assert_select "button", "S'abonner"
    end
  end

  test "a member with no credits sees the offers in the composer's paywall" do
    @user.update_columns(credit_balance: 0)
    post conversation_messages_path(conversations(:member_june)), params: { content: "Hello" }, as: :turbo_stream
    assert_response :payment_required
    assert_select ".paywall button", text: "Buy", count: 2
    assert_select ".paywall button", text: "Subscribe"
  end

  test "the amount can't come from the browser: unknown products and extra params change nothing" do
    post checkouts_path, params: { product: "pack_50", amount_cents: 1, credits: 9999 }
    assert_equal [ 499, 50 ], @user.payments.last.values_at(:amount_cents, :credits)

    assert_no_difference -> { Payment.count } do
      post checkouts_path, params: { product: "free_money" }
      assert_response :unprocessable_entity
    end
  end

  test "a guest is sent to create an account before paying" do
    sign_out
    sign_in_as users(:guest)
    assert_no_difference -> { Payment.count } do
      post checkouts_path, params: { product: "pack_50" }
    end
    assert_redirected_to new_registration_path
  end

  test "the checkout page of a forged or expired token is gone, and the sandbox disappears when another provider is active" do
    get "/sandbox/checkout/forged"
    assert_response :gone

    path = start_checkout("pack_50")
    with_env(PAYMENTS_PROVIDER: "stripe") do
      get path
      assert_response :not_found
    end
  end

  test "a provider that isn't configured creates nothing and tells the user" do
    with_env(PAYMENTS_PROVIDER: "stripe", STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: nil) do
      assert_no_difference -> { Payment.count } do
        post checkouts_path, params: { product: "pack_50" }
      end
    end
    assert_redirected_to account_path
    assert_equal I18n.t("payments.checkouts.create.unavailable"), flash[:alert]
  end

  test "a provider that refuses the checkout leaves a failed payment and charges nothing" do
    Payments::Registry.register("refusing", "RefusingProvider")
    with_env(PAYMENTS_PROVIDER: "refusing") { post checkouts_path, params: { product: "pack_50" } }

    assert_redirected_to account_path
    assert @user.payments.last.failed?
    assert_equal 5, @user.reload.credit_balance
  end

  test "CSRF protection stays on for the buy button" do
    ActionController::Base.allow_forgery_protection = true
    post checkouts_path, params: { product: "pack_50" }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
