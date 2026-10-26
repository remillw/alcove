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

  def refund_event(payment, cents, refund_id, **attrs)
    event(:payment_refunded, provider: payment.provider, external_id: payment.external_id, amount_cents: cents, refund_id:, **attrs)
  end

  def paid_pack(external_id)
    create_payment.tap { Payments::Settlement.call(paid_event(_1, external_id:)) }.reload # 5 -> 55 credits
  end

  test "a full refund takes the credits back, once, and the payment is refunded" do
    payment = paid_pack("pay_r")
    refund = refund_event(payment, 499, "re_1")
    2.times { Payments::Settlement.call(refund) }
    Payments::Settlement.call(refund_event(payment, 499, "re_1")) # same refund, another event

    assert payment.reload.refunded?
    assert_equal [ 499, 50 ], payment.values_at(:refunded_cents, :credits_refunded)
    assert_equal 5, @user.reload.credit_balance
    assert_equal 1, CreditEntry.where(idempotency_key: "refund:sandbox:re_1").count
  end

  test "a refund after the credits were spent takes what is left, never below zero, and says so" do
    payment = paid_pack("pay_s")
    Credits.post!(user: @user, amount: -40, kind: :reserve, key: "spent:1") # 55 -> 15
    Payments::Settlement.call(refund_event(payment, 499, "re_s"))

    assert_equal 0, @user.reload.credit_balance
    entry = CreditEntry.find_by!(idempotency_key: "refund:sandbox:re_s")
    assert_equal(-15, entry.amount)
    assert_equal({ "requested" => -50, "shortfall" => 35, "reason" => "refund", "payment_id" => payment.id, "refund_cents" => 499 }, entry.metadata)
    assert_empty Credits.drifted_user_ids
  end

  test "a partial refund takes back credits pro rata and leaves the payment partially_refunded" do
    payment = paid_pack("pay_p")
    Payments::Settlement.call(refund_event(payment, 100, "re_p")) # 50 * 100 / 499 = 10.02 -> 10

    assert payment.reload.partially_refunded?
    assert_equal [ 100, 10 ], payment.values_at(:refunded_cents, :credits_refunded)
    assert_equal 45, @user.reload.credit_balance
    assert_equal(-10, CreditEntry.find_by!(idempotency_key: "refund:sandbox:re_p").amount)
  end

  test "partial refunds accumulate: the rounding is on the running total, so the sum is exact and the last one finishes the job" do
    payment = paid_pack("pay_m")
    # 50 credits for 499 cents. Rounded one by one these would be 10 + 10 + 10 + 10 + 10 = 50 by luck; the cumulative
    # rule gives 10, 20 (200c = 20.04), 30 (300c = 30.06), then the rest.
    [ [ 100, "re_a", 10 ], [ 100, "re_b", 20 ], [ 100, "re_c", 30 ] ].each do |cents, id, credits|
      Payments::Settlement.call(refund_event(payment, cents, id))
      assert_equal credits, payment.reload.credits_refunded
      assert payment.partially_refunded?
    end
    assert_equal 25, @user.reload.credit_balance

    Payments::Settlement.call(refund_event(payment, 199, "re_d"))
    assert payment.reload.refunded?
    assert_equal [ 499, 50 ], payment.values_at(:refunded_cents, :credits_refunded)
    assert_equal 5, @user.reload.credit_balance
    assert_equal [ -10, -10, -10, -20 ], CreditEntry.where("idempotency_key LIKE 'refund:sandbox:%'").order(:id).pluck(:amount)
  end

  test "rounding is half up on the cumulative total" do
    payment = create_payment(amount_cents: 300, credits: 5) # 1 cent = 0.01666 credit
    # 29c = 0.483 credit -> 0, 30c = exactly 0.5 -> 1 (half up), 89c = 1.48 -> 1, 90c = 1.5 -> 2
    assert_equal [ 0, 0, 1, 1, 2, 3, 5 ], [ 0, 29, 30, 89, 90, 150, 300 ].map { payment.credits_for(_1) }
  end

  test "a refund too small to be worth a credit is recorded but moves nothing, and is not counted twice" do
    payment = create_payment(amount_cents: 300, credits: 5).tap { Payments::Settlement.call(paid_event(_1, external_id: "pay_t", amount_cents: 300)) }.reload
    2.times { Payments::Settlement.call(refund_event(payment, 29, "re_tiny")) }

    assert payment.reload.partially_refunded?
    assert_equal [ 29, 0 ], payment.values_at(:refunded_cents, :credits_refunded)
    assert_equal 10, @user.reload.credit_balance
    assert_not CreditEntry.exists?(idempotency_key: "refund:sandbox:re_tiny")
  end

  test "refunds beyond the amount charged are cut to what is left and reported, credits never exceed what was bought" do
    payment = paid_pack("pay_o")
    Payments::Settlement.call(refund_event(payment, 400, "re_1"))
    reported = []
    subscriber = Class.new { define_method(:report) { |error, **| reported << error.message } }.new
    Rails.error.subscribe(subscriber)
    Payments::Settlement.call(refund_event(payment, 400, "re_2")) # only 99 left
    Payments::Settlement.call(refund_event(payment, 50, "re_3")) # nothing left
    Rails.error.unsubscribe(subscriber)

    assert payment.reload.refunded?
    assert_equal [ 499, 50 ], payment.values_at(:refunded_cents, :credits_refunded)
    assert_equal 5, @user.reload.credit_balance
    assert_equal 50, -CreditEntry.where("idempotency_key LIKE 'refund:sandbox:%'").sum(:amount)
    assert_equal 2, reported.size
  end

  test "partial refunds with spent credits clamp each time and the balance stays at zero" do
    payment = paid_pack("pay_c")
    Credits.post!(user: @user, amount: -52, kind: :reserve, key: "spent:2") # 55 -> 3
    Payments::Settlement.call(refund_event(payment, 250, "re_x")) # 25 credits wanted, 3 available
    Payments::Settlement.call(refund_event(payment, 249, "re_y")) # 25 more, 0 available

    assert_equal 0, @user.reload.credit_balance
    assert_equal 50, payment.reload.credits_refunded
    assert_equal({ "requested" => -25, "shortfall" => 22 }, CreditEntry.find_by!(idempotency_key: "refund:sandbox:re_x").metadata.slice("requested", "shortfall"))
    assert_equal 0, CreditEntry.find_by!(idempotency_key: "refund:sandbox:re_y").amount
    assert_empty Credits.drifted_user_ids
  end

  test "a refund for a payment that was never paid, or for an unknown payment, changes nothing" do
    pending = create_payment.tap { _1.update!(external_id: "pay_pending") }
    Payments::Settlement.call(refund_event(pending, 100, "re_1"))
    assert pending.reload.pending?

    assert_nothing_raised { Payments::Settlement.call(event(:payment_refunded, external_id: "nope", amount_cents: 1, refund_id: "re_z")) }
    assert_equal 5, @user.reload.credit_balance
  end

  test "a replayed renewal invoice does not undo a refund" do
    payment = create_payment(product: "regular")
    paid = renewal_event(payment, period_start: Time.utc(2026, 11, 1))
    Payments::Settlement.call(paid)
    renewal = Payment.find_by!(external_id: paid.external_id)
    Payments::Settlement.call(refund_event(renewal, 999, "re_sub"))
    Payments::Settlement.call(renewal_event(payment, period_start: Time.utc(2026, 11, 1), id: "another-delivery"))

    assert renewal.reload.refunded?
  end

  # ---- cancellation --------------------------------------------------------------------------------------------

  def active_subscription(payment = create_payment(product: "regular"))
    Payments::Settlement.call(renewal_event(payment, period_start: Time.current.beginning_of_day))
    Subscription.find_by!(external_id: "sub_1")
  end

  test "an update schedules the end of the period, another takes it back, both leave the plan active" do
    subscription = active_subscription
    Payments::Settlement.call(event(:subscription_updated, subscription_id: "sub_1", cancel_at_period_end: true))
    assert subscription.reload.cancel_scheduled?
    assert subscription.active?

    Payments::Settlement.call(event(:subscription_updated, subscription_id: "sub_1", cancel_at_period_end: false))
    assert_not subscription.reload.cancel_at_period_end?
    assert_equal 305, @user.reload.credit_balance # no credit moved either way
  end

  test "the effective end comes from the deleted event: canceled once, and a late update can't revive it" do
    subscription = active_subscription
    Payments::Settlement.call(event(:subscription_updated, subscription_id: "sub_1", cancel_at_period_end: true))
    2.times { Payments::Settlement.call(event(:subscription_canceled, subscription_id: "sub_1")) }
    first_end = subscription.reload.canceled_at
    Payments::Settlement.call(event(:subscription_updated, subscription_id: "sub_1", cancel_at_period_end: false))

    assert subscription.reload.canceled?
    assert_equal first_end, subscription.canceled_at
    assert subscription.cancel_at_period_end?
    assert_nil @user.active_subscription
  end

  test "an update for a subscription we don't know yet is ignored when harmless and reported when it schedules an end" do
    assert_nothing_raised { Payments::Settlement.call(event(:subscription_updated, subscription_id: "sub_early", cancel_at_period_end: false)) }
    assert_nothing_raised { Payments::Settlement.call(event(:subscription_updated, subscription_id: "sub_early", cancel_at_period_end: true)) }
    assert_equal 0, Subscription.count
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
