require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "log in and out" do
    post session_path, params: { email_address: "member@example.com", password: "password12" }
    assert_redirected_to root_path
    assert cookies[:session_id]
    delete session_path
    assert_redirected_to root_path
  end

  test "wrong password" do
    post session_path, params: { email_address: "member@example.com", password: "nope" }
    assert_redirected_to new_session_path
  end
end
