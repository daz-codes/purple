require "test_helper"

class Account::SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @other_device = @user.sessions.create!(user_agent: "Firefox on Linux", ip_address: "192.0.2.10")
  end

  test "destroy revokes another of your sessions" do
    sign_in_as @user

    assert_difference -> { Session.count }, -1 do
      delete account_session_path(@other_device)
    end
    assert_redirected_to account_path
  end

  test "destroy on the current session signs you out" do
    sign_in_as @user
    current = Current.session

    delete account_session_path(current)

    assert_redirected_to new_session_path
    assert_not Session.exists?(current.id)
  end

  test "cannot revoke another user's session" do
    someone_else = users(:two).sessions.create!
    sign_in_as @user

    delete account_session_path(someone_else)

    assert_response :not_found
    assert Session.exists?(someone_else.id)
  end

  test "sign out everywhere else keeps only the current session" do
    sign_in_as @user
    current = Current.session

    delete account_other_sessions_path

    assert_equal [ current ], @user.sessions.reload.to_a
  end

  test "requires sign-in" do
    delete account_session_path(@other_device)
    assert_redirected_to new_session_path
    assert Session.exists?(@other_device.id)
  end
end
