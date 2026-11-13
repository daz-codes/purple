require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = User.take }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "correct horse battery" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "new redirects a signed-in user" do
    sign_in_as(@user)
    get new_session_path
    assert_redirected_to root_path
  end

  test "create does not add another session for a signed-in user" do
    sign_in_as(@user)
    assert_no_difference -> { @user.sessions.count } do
      post session_path, params: { email_address: @user.email_address, password: "correct horse battery" }
    end
    assert_redirected_to root_path
  end

  test "create returns to the page that asked for sign-in" do
    get account_path
    assert_redirected_to new_session_path

    post session_path, params: { email_address: @user.email_address, password: "correct horse battery" }
    assert_redirected_to account_url
  end

  test "an idle session is no longer accepted" do
    sign_in_as(@user)
    Current.session.update_columns(updated_at: (Session::IDLE_TIMEOUT + 1.day).ago)

    get account_path
    assert_redirected_to new_session_path
  end

  test "a session past the absolute timeout is no longer accepted" do
    sign_in_as(@user)
    Current.session.update_columns(created_at: (Session::ABSOLUTE_TIMEOUT + 1.day).ago)

    get account_path
    assert_redirected_to new_session_path
  end

  test "destroy" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
