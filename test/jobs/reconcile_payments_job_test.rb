require "test_helper"

# A provider the test controls, registered like any adapter: also shows the registry is open to new ones.
class FakeProvider < Payments::Provider
  cattr_accessor :answers, default: {}

  def fetch_event(payment) = answers[payment.token]
end

class ReconcilePaymentsJobTest < ActiveSupport::TestCase
  include PaymentsTestHelper

  setup do
    @user = users(:member)
    Payments::Registry.register("fake", "FakeProvider")
    FakeProvider.answers = {}
  end

  test "a payment paid at the provider whose webhook never came is caught up, once" do
    payment = create_payment(provider: "fake", created_at: 2.hours.ago)
    FakeProvider.answers[payment.token] = paid_event(payment, external_id: "fake_1")
    2.times { ReconcilePaymentsJob.perform_now }

    assert payment.reload.paid?
    assert_equal 55, @user.reload.credit_balance
  end

  test "a payment the provider says expired is closed" do
    payment = create_payment(provider: "fake", created_at: 2.hours.ago)
    FakeProvider.answers[payment.token] = event(:payment_expired, provider: "fake", token: payment.token)
    ReconcilePaymentsJob.perform_now

    assert payment.reload.expired?
  end

  test "recent payments are not asked about, and a still-open one waits for the next night" do
    recent = create_payment(provider: "fake", created_at: 10.minutes.ago)
    open = create_payment(provider: "fake", created_at: 3.hours.ago)
    FakeProvider.answers[recent.token] = event(:payment_expired, provider: "fake", token: recent.token)
    ReconcilePaymentsJob.perform_now

    assert recent.reload.pending?
    assert open.reload.pending?
  end

  test "a payment the provider still knows nothing about after a day is expired" do
    old = create_payment(provider: "fake", created_at: 2.days.ago)
    ReconcilePaymentsJob.perform_now
    assert old.reload.expired?
  end

  test "an unconfigured provider is reported and the others still run" do
    broken = create_payment(provider: "stripe", created_at: 2.hours.ago) # no Stripe keys in the test environment
    fine = create_payment(provider: "fake", created_at: 2.hours.ago)
    FakeProvider.answers[fine.token] = paid_event(fine, external_id: "fake_2")

    with_env(STRIPE_SECRET_KEY: nil, STRIPE_WEBHOOK_SECRET: nil) { ReconcilePaymentsJob.perform_now }

    assert broken.reload.pending?
    assert fine.reload.paid?
  end

  test "the sandbox expires its own abandoned checkouts after the token's life" do
    abandoned = create_payment(created_at: 2.hours.ago)
    ReconcilePaymentsJob.perform_now
    assert abandoned.reload.expired?
  end
end
