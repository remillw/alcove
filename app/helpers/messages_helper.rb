module MessagesHelper
  # Replies are plain text; the characters may set titles in *italics*. Escaped first, then the one bit of markup.
  def message_html(text)
    ERB::Util.h(text).gsub(/\*\*(.+?)\*\*/, '\1').gsub(/(?<![\w*])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\w*])/, '<em>\1</em>').html_safe
  end
end
