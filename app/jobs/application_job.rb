class ApplicationJob < ActiveJob::Base
  # jobs speak the user's language: partials they broadcast and texts they put in prompts
  def in_locale_of(user, &) = I18n.with_locale(user&.locale.presence || I18n.default_locale, &)
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
