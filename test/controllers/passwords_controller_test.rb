require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { @user = users(:member) }

  test "known and unknown emails get the same answer; only the known one is mailed" do
    assert_enqueued_emails 1 do
      post passwords_path, params: { email_address: "Member@Example.com " }
    end
    known = [ response.status, response.location, flash[:notice] ]
    assert_no_enqueued_emails do
      post passwords_path, params: { email_address: "nobody@example.com" }
    end
    assert_equal known, [ response.status, response.location, flash[:notice] ]
  end

  test "a guest (no registered_at) is never mailed" do
    @user.update_columns(registered_at: nil)
    assert_no_enqueued_emails { post passwords_path, params: { email_address: @user.email_address } }
  end

  test "the mail is sent in the user's language" do
    @user.update!(locale: "fr")
    perform_enqueued_jobs { post passwords_path, params: { email_address: @user.email_address } }
    assert_equal "Réinitialisez votre mot de passe Alcove", ActionMailer::Base.deliveries.last.subject
  end

  test "a valid link shows the form and sets the password, closing every session" do
    @user.sessions.create!
    token = @user.password_reset_token
    get edit_password_path(token)
    assert_response :success
    patch password_path(token), params: { password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    assert_redirected_to new_session_path
    assert_equal 0, @user.sessions.count
    assert @user.reload.authenticate("brand-new-pass")
  end

  test "a link works only once" do
    token = @user.password_reset_token
    patch password_path(token), params: { password: "brand-new-pass", password_confirmation: "brand-new-pass" }
    get edit_password_path(token)
    assert_redirected_to new_password_path
    patch password_path(token), params: { password: "another-pass-1", password_confirmation: "another-pass-1" }
    assert_redirected_to new_password_path
    assert @user.reload.authenticate("brand-new-pass")
  end

  test "an expired or forged link is refused" do
    token = @user.password_reset_token
    travel_to((User::RESET_TTL + 1.minute).from_now) { get edit_password_path(token) }
    assert_redirected_to new_password_path
    get edit_password_path("garbage")
    assert_redirected_to new_password_path
  end

  test "mismatch or too short keeps the old password and the sessions" do
    @user.sessions.create!
    token = @user.password_reset_token
    patch password_path(token), params: { password: "brand-new-pass", password_confirmation: "different-pass" }
    assert_response :unprocessable_entity
    patch password_path(token), params: { password: "short", password_confirmation: "short" }
    assert_response :unprocessable_entity
    assert @user.reload.authenticate("password12")
    assert_equal 1, @user.sessions.count
  end

  test "requests are rate limited" do
    # the test cache is a null store, so give the limiter a counting one (it keeps its store from class load)
    store = ActiveSupport::Cache::MemoryStore.new
    limiter = ActionController::Base.cache_store
    limiter.define_singleton_method(:increment) { |key, amount = 1, **options| store.increment(key, amount, **options) || (store.write(key, amount, **options) && amount) }
    assert_no_enqueued_emails do
      6.times { post passwords_path, params: { email_address: "nobody@example.com" } }
    end
    assert_equal I18n.t("passwords.too_many"), flash[:alert]
  ensure
    limiter&.singleton_class&.send(:remove_method, :increment)
  end
end
