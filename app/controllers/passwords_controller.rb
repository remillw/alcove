class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[edit update]
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { redirect_to new_password_path, alert: I18n.t("passwords.too_many") }

  def new
  end

  # Same answer whether or not the email belongs to a member: no account enumeration.
  # The mail goes through the job queue, so timing doesn't give the answer away either.
  def create
    if (user = User.registered.find_by(email_address: params[:email_address].to_s.strip.downcase))
      PasswordsMailer.reset(user).deliver_later
    end
    redirect_to new_session_path, notice: t("passwords.sent")
  end

  def edit
  end

  def update
    if password_confirmed? && @user.update(password: params[:password])
      # whoever had the old password (or a stolen cookie) is signed out everywhere
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("passwords.updated")
    else
      @errors = @user.errors.full_messages.presence || [ t("passwords.mismatch") ]
      render :edit, status: :unprocessable_entity
    end
  end

  private

  # has_secure_password runs without validations here, so the confirmation is checked by hand.
  def password_confirmed?
    params[:password].present? && params[:password] == params[:password_confirmation]
  end

  # The token is signed, expires, and stops working once the password changes (single use).
  def set_user_by_token
    @user = User.registered.find_by_password_reset_token!(params[:token])
  rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
    redirect_to new_password_path, alert: t("passwords.invalid_link")
  end
end
