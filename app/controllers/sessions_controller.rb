class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { redirect_to new_session_path, alert: "Too many attempts. Try again later." }

  def new
  end

  def create
    if (user = User.where.not(registered_at: nil).authenticate_by(params.permit(:email_address, :password)))
      terminate_session if resume_session
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: "That email and password don't match."
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end
end
