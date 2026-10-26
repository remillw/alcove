class Report < ApplicationRecord
  KINDS = %w[user_flag distress blocked_input blocked_output].freeze
  belongs_to :message, optional: true
  belongs_to :user, optional: true
  validates :kind, inclusion: { in: KINDS }

  after_create_commit :tell_hermes, if: -> { kind.in?(%w[user_flag distress]) }

  private

  # a human should look: the id and the character, never the message itself
  def tell_hermes
    character = message&.conversation&.character&.name
    if kind == "distress"
      Hermes.notify("distress", title: "Message de détresse", body: "Une personne a écrit un message de détresse à #{character}. Les numéros d'aide lui ont été donnés. Signalement ##{id}.")
    else
      Hermes.notify("report", title: "Réponse signalée", body: "Une réponse de #{character} a été signalée. Signalement ##{id}, message ##{message_id}.")
    end
  end
end
