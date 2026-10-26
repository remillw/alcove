class MemoriesController < ApplicationController
  before_action :require_user

  def destroy
    memory = Memory.joins(:conversation).where(conversations: { user_id: current_user.id }).find(params[:id])
    memory.destroy!
    render turbo_stream: turbo_stream.remove(memory)
  end
end
