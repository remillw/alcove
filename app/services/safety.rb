# First line of defence, before any API call: a crisis gets a human answer with real helplines (and no model
# call, no credit spent); clearly forbidden requests are refused. The platform rules in the system prompt and the
# model's own safeguards are the second line. Patterns stay deliberately narrow: a false positive on a sad day
# would be worse than useless.
module Safety
  DISTRESS = Regexp.union(
    /\b(kill|hurt|harm)(ing)?\s+myself\b/i, /\bsuicid(e|al)\b/i, /\bend\s+(it\s+all|my\s+life)\b/i,
    /\bwant\s+to\s+die\b/i, /\bself[-\s]?harm\b/i, /\bcut(ting)?\s+myself\b/i,
    /\bme\s+(tuer|suicider)\b/i, /\benvie\s+de\s+mourir\b/i, /\ben\s+finir\b.*\bvie\b/i
  )
  FORBIDDEN = Regexp.union(
    /\b(child|kid|minor|underage|teen)\b.{0,40}\b(sex|nude|naked|porn)/i,
    /\b(sex|nude|naked|porn).{0,40}\b(child|kid|minor|underage)\b/i
  )

  DISTRESS_REPLY = <<~TEXT.squish
    I'm really glad you told me, and I'm worried about you. I'm an AI and I can't be the help you need right now,
    but people can. If you're in danger, call your local emergency number now. In France, call or text 3114
    (free, 24/7). In the US, call or text 988. In the UK and Ireland, Samaritans: 116 123. Elsewhere,
    findahelpline.com lists services by country. Please reach out to someone near you too. I'm still here if you
    want to keep talking.
  TEXT
  REFUSAL_REPLY = "That's not something I'll take part in. Let's talk about something else."

  def self.check(text)
    return :distress if text.match?(DISTRESS)
    return :forbidden if text.match?(FORBIDDEN)
    :ok
  end
end
