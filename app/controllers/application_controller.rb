class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :current_user
  around_action :switch_locale

  private

  # ?locale=fr (the switch in the footer) wins, then the cookie, then the browser's language; English otherwise.
  # A signed-in user's choice is saved, so their characters greet them and the safety texts use that language.
  def switch_locale(&)
    chosen = params[:locale].presence_in(%w[en fr])
    cookies.permanent[:locale] = chosen if chosen
    locale = chosen || cookies[:locale].presence_in(%w[en fr]) || browser_locale
    I18n.with_locale(locale) do
      resume_session
      Current.user.update_column(:locale, locale) if Current.user && Current.user.locale != locale
      yield
    end
  end

  def browser_locale = request.headers["Accept-Language"].to_s.downcase.start_with?("fr") ? "fr" : "en"

  def current_user = Current.user

  # a visitor gets a guest account the moment they start talking: no sign-up wall before the first reply
  def ensure_user!
    resume_session || start_new_session_for(User.create_guest!)
    Current.user
  end

  def require_user
    resume_session || redirect_to(root_path, alert: "Pick a character to start a conversation.")
  end
end
