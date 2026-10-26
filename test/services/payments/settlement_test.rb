require "test_helper"

class Payments::SettlementTest < ActiveSupport::TestCase
  include PaymentsTestHelper

  setup { @user = users(:member) } # 5 credits

  test "a paid pack credits the user once, under the payment's idempotency key" do
    payment = create_payment
    2.times { Payments::Settlement.call(paid_event(payment, external_id: "pay_9")) }

    assert payment.reload.paid?
    assert_equal "pay_9", payment.external_id
    assert_equal 55, @user.reload.credit_balance
    entry = CreditEntry.find_by!(idempotency_key: "payment:sandbox:pay_9")
    assert_equal [ "purchase", 50 ], [ entry.kind, entry.amount ]
  end

  test "a declined payment fails and gives nothing" do
    payment = create_payment
    Payments::Settlement.call(event(:payment_failed, token: payment.token))

    assert payment.reload.failed?
    assert_equal 5, @user.reload.credit_balance
  end

  test "an abandoned checkout expires" do
    payment = create_payment
    Payments::Settlement.call(event(:payment_expired, token: payment.token))
    assert payment.reload.expired?
  end

  test "money wins: a late success still pays a failed or expired payment, a late failure never unpays" do
    late = create_payment.tap { _1.expired! }
    Payments::Settlement.call(paid_event(late))
    assert late.reload.paid?

    Payments::Settlement.call(event(:payment_failed, token: late.token))
    Payments::Settlement.call(event(:payment_expired, token: late.token))
    assert late.reload.paid?
    assert_equal 55, @user.reload.credit_balance
  end

  test "a charge that differs from the catalogue credits nothing" do
    payment = create_payment
    Payments::Settlement.call(paid_event(payment, amount_cents: 1))

    assert payment.reload.failed?
    assert_equal 1, payment.metadata["mismatch"]["amount_cents"]
    assert_equal 5, @user.reload.credit_balance
  end

  test "an event about a reference we never issued is acknowledged without effect" do
    assert_nothing_raised { Payments::Settlement.call(event(:payment_succeeded, token: "nope", external_id: "x", amount_cents: 1, currency: "EUR")) }
    assert_equal 5, @user.reload.credit_balance
  end

  test "a full refund takes the credits back, once" do
    payment = create_payment
    Payments::Settlement.call(paid_event(payment, external_id: "pay_r"))
    refund = event(:payment_refunded, external_id: "pay_r", amount_cents: 499)
    2.times { Payments::Settlement.call(refund) }

    assert payment.reload.refunded?
    assert_equal 5, @user.reload.credit_balance
    assert_equal 1, CreditEntry.where(idempotency_key: "refund:sandbox:pay_r").count
  end

  test "a refund after the credits were spent takes what is left, never below zero, and says so" do
    payment = create_payment
    Payments::Settlement.call(paid_event(payment, external_id: "pay_s"))
    Credits.post!(user: @user, amount: -40, kind: :reserve, key: "spent:1") # 55 -> 15
    Payments::Settlement.call(event(:payment_refunded, external_id: "pay_s", amount_cents: 499))

    assert_equal 0, @user.reload.credit_balance
    entry = CreditEntry.find_by!(idempotency_key: "refund:sandbox:pay_s")
    assert_equal(-15, entry.amount)
    assert_equal({ "requested" => -50, "shortfall" => 35, "reason" => "refund", "payment_id" => payment.id }, entry.metadata)
    assert_empty Credits.drifted_user_ids
  end

  test "a partial refund leaves the credits alone" do
    payment = create_payment
    Payments::Settlement.call(paid_event(payment, external_id: "pay_p"))
    Payments::Settlement.call(event(:payment_refunded, external_id: "pay_p", amount_cents: 100))

    assert payment.reload.paid?
    assert_equal 55, @user.reload.credit_balance
  end

  test "the first subscription payment activates the plan and grants the month's credits" do
    payment = create_payment(product: "regular")
    start = Time.utc(2026, 11, 1, 10)
    Payments::Settlement.call(renewal_event(payment, period_start: start))

    subscription = Subscription.find_by!(external_id: "sub_1")
    assert subscription.active?
    assert_equal start, subscription.current_period_start
    assert payment.reload.paid?
    assert_equal subscription, payment.subscription
    assert_equal 305, @user.reload.credit_balance
    assert CreditEntry.exists?(idempotency_key: "subscription:#{subscription.id}:2026-11-01T10:00:00Z")
  end

  test "a renewal grants the next month once, with a payment row of its own" do
    payment = create_payment(product: "regular")
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 11, 1)))
    december = renewal_event(payment, period_start: Time.utc(2026, 12, 1))
    2.times { Payments::Settlement.call(december) }

    assert_equal 605, @user.reload.credit_balance
    assert_equal 2, @user.payments.paid.count
    assert_equal Time.utc(2026, 12, 1), Subscription.find_by!(external_id: "sub_1").current_period_start
  end

  test "an older renewal arriving late pays its month but doesn't move the period back" do
    payment = create_payment(product: "regular")
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 12, 1)))
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 11, 1)))

    assert_equal Time.utc(2026, 12, 1), Subscription.find_by!(external_id: "sub_1").current_period_start
    assert_equal 605, @user.reload.credit_balance
  end

  test "an unpaid renewal makes the subscription past_due and grants nothing; paying again reactivates it" do
    payment = create_payment(product: "regular")
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 11, 1)))
    Payments::Settlement.call(event(:subscription_past_due, subscription_id: "sub_1"))

    subscription = Subscription.find_by!(external_id: "sub_1")
    assert subscription.past_due?
    assert_equal 305, @user.reload.credit_balance

    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 12, 1)))
    assert subscription.reload.active?
  end

  test "a failed first payment of a subscription fails the pending payment" do
    payment = create_payment(product: "regular")
    Payments::Settlement.call(event(:subscription_past_due, subscription_id: "sub_new", token: payment.token))
    assert payment.reload.failed?
    assert_equal 0, Subscription.count
  end

  test "a canceled subscription stays canceled even if an old invoice arrives" do
    payment = create_payment(product: "regular")
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 11, 1)))
    Payments::Settlement.call(event(:subscription_canceled, subscription_id: "sub_1"))
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 11, 1), external_id: "in_other"))

    subscription = Subscription.find_by!(external_id: "sub_1")
    assert subscription.canceled?
    assert subscription.canceled_at
  end
end
