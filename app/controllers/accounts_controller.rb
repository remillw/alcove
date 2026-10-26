class AccountsController < ApplicationController
  before_action :require_user

  def show
    DailyCredits.top_up(current_user)
    @entries = current_user.credit_entries.order(id: :desc).limit(30)
    # back from the provider's page: the credits themselves arrive with the webhook, which may be a moment behind
    flash.now[:notice] = t(".checkout_#{params[:checkout]}") if params[:checkout].in?(%w[success cancelled])
  end

  # GDPR: everything we hold about you, as JSON
  def export
    send_data AccountExport.new(current_user).to_json, filename: "alcove-#{Date.current}.json", type: :json
  end

  def destroy
    current_user.destroy!
    cookies.delete(:session_id)
    redirect_to root_path, notice: t("accounts.deleted"), status: :see_other
  end
end
