require "test_helper"

class MessagesHelperTest < ActionView::TestCase
  test "titles in asterisks become italics, everything else is escaped" do
    assert_equal "Try <em>Piranesi</em> &lt;b&gt;now&lt;/b&gt;", message_html("Try *Piranesi* <b>now</b>")
    assert_equal "2 * 3 = 6", message_html("2 * 3 = 6")
  end
end
