class MessagesController < ApplicationController
  before_action :require_user
  rate_limit to: 12, within: 1.minute, by: -> { Current.user&.id || request.remote_ip }, only: :create,
    with: -> { render_composer_error(I18n.t("messages.too_fast"), :too_many_requests) }

  def create
    @conversation = current_user.conversations.find(params[:conversation_id])
    return render_composer_error(t("messages.resting"), :service_unavailable) if Breaker.open?

    result = Turn.take!(conversation: @conversation, content: params[:content], nonce: params[:nonce].presence || SecureRandom.uuid)
    case result.error
    when nil
      @message, @reply = result.message, result.reply
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @conversation }
      end
    when :no_credits then render_composer_error(:no_credits, :payment_required)
    when :busy then render_composer_error(t("messages.busy", name: @conversation.character.first_name), :conflict)
    when :invalid then render_composer_error(t("messages.too_long", count: Message::MAX_LENGTH), :unprocessable_entity)
    end
  end

  def cancel
    reply = Message.joins(:conversation).where(conversations: { user_id: current_user.id }).find(params[:id])
    reply.update!(cancel_requested_at: Time.current) if reply.active?
    head :no_content
  end

  def report
    message = Message.joins(:conversation).where(conversations: { user_id: current_user.id }).find(params[:id])
    Report.create!(message:, user: current_user, kind: "user_flag", note: params[:note].to_s.first(500))
    render turbo_stream: turbo_stream.replace(helpers.dom_id(message, :report), html: helpers.tag.span(t("messages.message.reported"), class: "line__flagged"))
  end

  private

  def render_composer_error(error, status)
    @conversation ||= current_user.conversations.find(params[:conversation_id])
    render turbo_stream: turbo_stream.replace("composer", partial: "messages/composer",
      locals: { conversation: @conversation, error: }), status:
  end
end
