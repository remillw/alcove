# When you come back after a while, the character opens with a hand-written line (no API call, no credit) that
# picks up the last thing they kept for you: "There you are. Did Piranesi survive the week?"
module Welcome
  def self.back(conversation, now: Time.current)
    last = conversation.messages.last or return
    return if last.active? || last.created_at > now - 3.hours

    returns = conversation.character.returns
    gap = now - last.created_at
    item = conversation.keepsake_items.order(updated_at: :desc).pick(:title)
    template = if gap < 20.hours then returns["soon"]
    elsif gap < 7.days && item then returns["days"]
    else returns["long"]
    end
    return if template.blank?

    conversation.messages.create!(role: "assistant", content: format(template, item: item.to_s))
  end
end
