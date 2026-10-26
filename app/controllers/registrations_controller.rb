class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { redirect_to new_registration_path, alert: "Too many attempts. Try again later." }

  def new
    resume_session
    redirect_to account_path if current_user&.registered?
  end

  # a guest keeps their conversations: the same user row gets an email and a password
  def create
    return redirect_to(new_registration_path, alert: "You need to be 18 or older to use Alcove.") unless params[:adult] == "1" && params[:terms] == "1"

    user = resume_session ? current_user : User.new
    if user.registered?
      redirect_to account_path
    elsif user.persisted? ? register(user) : register(User.create!)
      start_new_session_for(@registered) unless resume_session
      redirect_to session.delete(:return_to_after_authenticating) || after_signup_path, notice: "Welcome to Alcove. #{User::SIGNUP_CREDITS} credits are yours."
    else
      @errors = @registered.errors.full_messages
      render :new, status: :unprocessable_entity
    end
  end

  private

  def register(user)
    @registered = user
    user.register!(email_address: params[:email_address], password: params[:password], display_name: params[:display_name])
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def after_signup_path
    last = @registered.conversations.order(last_message_at: :desc).first
    last ? conversation_path(last) : root_path
  end
end
