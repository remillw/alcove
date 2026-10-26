# Operator tools for the sandbox provider (demo and tests). Nothing here is routed: users can't trigger a refund or an
# end of subscription, they go through Payments::Webhooks like a real provider's events.
namespace :payments do
  desc "Sandbox: refund a payment, fully or partially. payments:sandbox_refund[PAYMENT_ID] or [PAYMENT_ID,AMOUNT_CENTS]"
  task :sandbox_refund, %i[payment_id amount_cents] => :environment do |_, args|
    payment = Payment.find(args.fetch(:payment_id))
    refund_id = Payments.provider("sandbox").refund(payment, amount_cents: args[:amount_cents]&.to_i)
    payment.reload
    puts "refund #{refund_id}: payment #{payment.id} is #{payment.status} (#{payment.refunded_cents}/#{payment.amount_cents} cents, #{payment.credits_refunded}/#{payment.credits} credits)"
  end

  desc "Sandbox: end a subscription now, as at the close of its last period. payments:sandbox_end_subscription[SUBSCRIPTION_ID]"
  task :sandbox_end_subscription, %i[subscription_id] => :environment do |_, args|
    subscription = Subscription.find(args.fetch(:subscription_id))
    Payments.provider("sandbox").end_subscription(subscription)
    puts "subscription #{subscription.id} is #{subscription.reload.status}"
  end
end
