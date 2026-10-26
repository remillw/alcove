class AccountsController < ApplicationController
  before_action :require_user

  def show
    DailyCredits.top_up(current_user)
    @entries = current_user.credit_entries.order(id: :desc).limit(30)
  end

  # GDPR: everything we hold about you, as JSON
  def export
    send_data AccountExport.new(current_user).to_json, filename: "alcove-#{Date.current}.json", type: :json
  end

  def destroy
    current_user.destroy!
    cookies.delete(:session_id)
    redirect_to root_path, notice: "Your account and all your conversations have been deleted.", status: :see_other
  end
end
