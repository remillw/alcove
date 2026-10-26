class ConversationsController < ApplicationController
  allow_unauthenticated_access only: :create
  before_action :require_user, except: :create
  before_action :set_conversation, only: %i[show destroy]

  def index
    @conversations = current_user.conversations.includes(:character).order(last_message_at: :desc)
  end

  def show
    DailyCredits.top_up(current_user)
    @messages = @conversation.messages.last(80)
  end

  # "Start talking": confirms age and the AI notice, creates the guest account if needed, opens with the greeting
  def create
    character = Character.published.find_by!(slug: params[:id])
    unless params[:adult] == "1" || current_user_adult?
      return redirect_to character_path(character), alert: "Please confirm you're 18 or older to start."
    end

    user = ensure_user!
    user.update!(adult_confirmed_at: Time.current) unless user.adult?
    conversation = user.conversations.create_or_find_by!(character:)
    conversation.messages.create!(role: "assistant", content: character.greeting) if conversation.messages.none?
    redirect_to conversation
  end

  def destroy
    @conversation.destroy!
    redirect_to conversations_path, notice: "Conversation and memories deleted.", status: :see_other
  end

  private

  def set_conversation = @conversation = current_user.conversations.includes(:character).find(params[:id])
  def current_user_adult? = resume_session && current_user.adult?
end
