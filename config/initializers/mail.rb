# Production fallback when SMTP_ADDRESS isn't set: nothing is sent, the whole email (including a reset
# link, so treat the log as sensitive) goes to the Rails log and the user sees the same page as ever.
class LogMailDelivery
  def initialize(_settings = {}); end

  def deliver!(mail)
    Rails.logger.info("[mail not sent: SMTP_ADDRESS is not set]\n#{mail}")
  end
end

ActionMailer::Base.add_delivery_method :log, LogMailDelivery
