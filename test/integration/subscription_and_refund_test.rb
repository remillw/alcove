require "test_helper"
require "rake"

class DownProvider < Payments::Provider
  def cancel_subscription(_) = raise(Payments::Error, "provider is down")
  def resume_subscription(_) = raise(Payments::Error, "provider is down")
end

# Cancel / resume from the account page, and refunds, with the sandbox: every state change arrives as a signed event.
class SubscriptionAndRefundTest < ActionDispatch::IntegrationTest
  include PaymentsTestHelper

  setup do
    @user = users(:member) # 5 credits
    sign_in_as @user
    @provider = Payments::Providers::Sandbox.new
  end

  def subscribe
    post checkouts_path, params: { product: "regular" }
    post "#{URI(response.location).path}/pay"
    @user.subscriptions.sole
  end

  def buy_pack
    post checkouts_path, params: { product: "pack_50" }
    post "#{URI(response.location).path}/pay"
    @user.payments.order(:id).last
  end

  # ---- cancel and resume -----------------------------------------------------------------------------------------

  test "the account page offers to cancel an active subscription, behind a confirmation" do
    subscribe
    get account_path
    assert_select "p.muted", /Regular subscription is active until/
    assert_select "form[action='#{cancellation_path}'][data-turbo-confirm]" do
      assert_select "button", "Cancel subscription"
    end
    assert_select "button", text: "Resume subscription", count: 0
  end

  test "cancelling stops at the end of the period: still active, status shown, resume offered" do
    subscription = subscribe
    assert_difference -> { WebhookEvent.count }, 1 do
      post cancellation_path
    end
    assert_redirected_to account_path

    assert subscription.reload.cancel_scheduled?
    assert subscription.active?
    assert_equal 305, @user.reload.credit_balance # the month's credits are kept

    follow_redirect!
    assert_select ".flash", /Cancellation requested/
    assert_select "p.muted", /Regular subscription ends on #{Regexp.escape(subscription.current_period_end.strftime("%Y-%m-%d"))}/
    assert_select "button", "Resume subscription"
    assert_select "button", text: "Cancel subscription", count: 0
    assert_select "button", text: "Subscribe", count: 0 # still the plan holder until the end
  end

  test "resuming while the period runs takes the cancellation back" do
    subscription = subscribe
    post cancellation_path
    delete cancellation_path

    assert_redirected_to account_path
    assert_not subscription.reload.cancel_scheduled?
    follow_redirect!
    assert_select ".flash", /will renew as usual/
    assert_select "button", "Cancel subscription"
  end

  test "cancelling twice is harmless, resuming without a pending cancellation is refused" do
    subscribe
    delete cancellation_path
    assert_equal I18n.t("payments.cancellations.destroy.too_late"), flash[:alert]

    post cancellation_path
    assert_no_difference -> { WebhookEvent.count } do
      post cancellation_path
    end
    assert_equal I18n.t("payments.cancellations.create.already"), flash[:notice]
  end

  test "the effective end arrives as the provider's event: canceled, plan gone, offers back, credits untouched" do
    subscription = subscribe
    post cancellation_path
    @provider.end_subscription(subscription)

    assert subscription.reload.canceled?
    assert subscription.canceled_at
    assert_equal 305, @user.reload.credit_balance
    get account_path
    assert_select "button", "Subscribe"
    assert_select "button", text: "Cancel subscription", count: 0

    delete cancellation_path # too late to resume: it's over
    assert_equal I18n.t("payments.cancellations.none"), flash[:alert]
  end

  test "the end event is processed once: a replay of the same signed delivery does nothing" do
    subscription = subscribe
    body = { id: "evt_end_1", type: "subscription.canceled", created: Time.now.to_i, data: { subscription_id: subscription.external_id } }.to_json
    2.times do
      post "/webhooks/sandbox", params: body, headers: sandbox_headers(body)
      assert_response :ok
    end
    canceled_at = subscription.reload.canceled_at

    assert subscription.canceled?
    assert_equal 1, WebhookEvent.where(event_id: "evt_end_1").count
    travel(1.minute) { post "/webhooks/sandbox", params: body, headers: sandbox_headers(body) }
    assert_equal canceled_at, subscription.reload.canceled_at
  end

  test "a signed cancel event with a bad signature is refused and changes nothing" do
    subscription = subscribe
    body = { id: "evt_forged", type: "subscription.updated", created: Time.now.to_i, data: { subscription_id: subscription.external_id, cancel_at_period_end: true } }.to_json
    post "/webhooks/sandbox", params: body, headers: sandbox_headers(body, secret: "nope")

    assert_response :bad_request
    assert_not subscription.reload.cancel_scheduled?
  end

  test "you can't cancel without a subscription, nor as a guest" do
    post cancellation_path
    assert_redirected_to account_path
    assert_equal I18n.t("payments.cancellations.none"), flash[:alert]

    sign_out
    post cancellation_path
    assert_redirected_to new_session_path
  end

  test "one user's cancel never touches another's subscription" do
    other = users(:guest)
    mine = subscribe
    theirs = Subscription.create!(user: other, provider: "sandbox", external_id: "sbx_sub_other", product_key: "regular", current_period_end: 20.days.from_now)
    post cancellation_path

    assert mine.reload.cancel_scheduled?
    assert_not theirs.reload.cancel_scheduled?
  end

  test "when the provider is down nothing changes and the user is told" do
    Payments::Registry.register("down", "DownProvider")
    subscription = subscribe.tap { _1.update!(provider: "down") }
    post cancellation_path
    assert_redirected_to account_path
    assert_equal I18n.t("payments.cancellations.create.unavailable"), flash[:alert]
    assert_not subscription.reload.cancel_scheduled?

    subscription.update!(cancel_at_period_end: true)
    delete cancellation_path
    assert_equal I18n.t("payments.cancellations.destroy.unavailable"), flash[:alert]
    assert subscription.reload.cancel_scheduled?
  end

  test "the subscription's own provider is asked, whatever PAYMENTS_PROVIDER says now" do
    subscription = subscribe # sandbox
    with_env(PAYMENTS_PROVIDER: "stripe", STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: nil) { post cancellation_path }
    assert subscription.reload.cancel_scheduled?
  end

  test "French copy" do
    subscribe
    post cancellation_path
    I18n.backend.store_translations(:fr, time: { formats: { short: "%d/%m %H:%M" } })
    get account_path(locale: "fr")
    assert_select "p.muted", /Votre abonnement Regular se termine le/
    assert_select "button", "Reprendre l'abonnement"
  end

  # ---- sandbox refunds (operator tool, not user-facing) ----------------------------------------------------------

  test "a full sandbox refund returns the credits and the payment is refunded" do
    pack = buy_pack
    @provider.refund(pack)

    assert pack.reload.refunded?
    assert_equal 5, @user.reload.credit_balance
  end

  test "partial sandbox refunds add up, never past the amount charged" do
    pack = buy_pack # 55 credits
    @provider.refund(pack, amount_cents: 100)
    assert pack.reload.partially_refunded?
    assert_equal 45, @user.reload.credit_balance

    @provider.refund(pack, amount_cents: 100)
    assert_equal 35, @user.reload.credit_balance # 200c -> 20 credits in total

    assert_raises(Payments::Error) { @provider.refund(pack, amount_cents: 300) } # only 299 left
    assert_raises(Payments::Error) { @provider.refund(pack, amount_cents: 0) }
    assert_equal 35, @user.reload.credit_balance

    @provider.refund(pack) # the rest
    assert pack.reload.refunded?
    assert_equal 5, @user.reload.credit_balance
    assert_raises(Payments::Error) { @provider.refund(pack) }
    assert_equal 3, CreditEntry.where("idempotency_key LIKE 'refund:sandbox:sbx_re_%'").count
    assert_empty Credits.drifted_user_ids
  end

  test "a replayed refund delivery counts once" do
    pack = buy_pack
    body = { id: "evt_re", type: "payment.refunded", created: Time.now.to_i,
             data: { payment_id: pack.external_id, refund_id: "sbx_re_fixed", amount_cents: 100, currency: "EUR" } }.to_json
    2.times { post "/webhooks/sandbox", params: body, headers: sandbox_headers(body) }
    # the same refund under another event id: still once
    other = body.sub("evt_re", "evt_re_bis")
    post "/webhooks/sandbox", params: other, headers: sandbox_headers(other)

    assert_equal 100, pack.reload.refunded_cents
    assert_equal 45, @user.reload.credit_balance
  end

  test "the rake tasks drive the same path" do
    Rails.application.load_tasks unless Rake::Task.task_defined?("payments:sandbox_refund")
    pack = buy_pack
    subscription = subscribe

    capture_io { Rake::Task["payments:sandbox_refund"].execute(Rake::TaskArguments.new(%i[payment_id amount_cents], [ pack.id, "100" ])) }
    assert pack.reload.partially_refunded?

    capture_io { Rake::Task["payments:sandbox_end_subscription"].execute(Rake::TaskArguments.new(%i[subscription_id], [ subscription.id ])) }
    assert subscription.reload.canceled?
  end

  test "no route lets a browser trigger a refund" do
    pack = buy_pack
    post "/payments/#{pack.id}/refund"
    assert_response :not_found
    assert_not Rails.application.routes.routes.any? { _1.path.spec.to_s.include?("refund") }
  end
end
