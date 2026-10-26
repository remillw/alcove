class ApplicationController < ActionController::Base
  include Authentication
  allow_browser versions: :modern
  stale_when_importmap_changes

  helper_method :current_user

  private

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
