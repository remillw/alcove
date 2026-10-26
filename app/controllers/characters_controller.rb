class CharactersController < ApplicationController
  allow_unauthenticated_access

  def index
    resume_session
    @characters = Character.published
    @conversations = current_user ? current_user.conversations.includes(:character).index_by(&:character_id) : {}
  end

  def show
    resume_session
    @character = Character.published.find_by!(slug: params[:id])
    @conversation = current_user&.conversations&.find_by(character: @character)
  end
end
