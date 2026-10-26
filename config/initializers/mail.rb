# Production fallback when SMTP_ADDRESS isn't set: nothing is sent and the user sees the same page as ever.
# The log gets the subject and a message id only: never the body, which may hold a password reset link.
class LogMailDelivery
  def initialize(_settings = {}); end

  def deliver!(mail)
    Rails.logger.warn("[mail not sent: SMTP_ADDRESS is not set] subject=#{mail.subject.inspect} message_id=#{mail.message_id}")
  end
end

ActionMailer::Base.add_delivery_method :log, LogMailDelivery
