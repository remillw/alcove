require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  test "signing up queues the welcome email" do
    assert_enqueued_emails 1 do
      post registration_path, params: { email_address: "new@example.com", password: "password12", adult: "1", terms: "1" }
    end
    assert_enqueued_email_with WelcomeMailer, :welcome, args: [ User.find_by!(email_address: "new@example.com") ]
  end

  test "a failed sign-up sends nothing" do
    assert_no_enqueued_emails do
      post registration_path, params: { email_address: "bad", password: "password12", adult: "1", terms: "1" }
    end
  end
end
