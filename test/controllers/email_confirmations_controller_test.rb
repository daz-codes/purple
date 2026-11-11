require "test_helper"

class EmailConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:unconfirmed) }

  test "show displays a confirm button without confirming (safe against link scanners)" do
    get email_confirmation_path(@user.email_confirmation_token)

    assert_response :success
    assert_select "button", "Confirm my email address"
    assert_not @user.reload.confirmed?
  end

  test "update confirms the user" do
    patch email_confirmation_path(@user.email_confirmation_token)

    assert @user.reload.confirmed?
    assert_redirected_to new_session_path
  end

  test "update when signed in returns home" do
    sign_in_as @user
    patch email_confirmation_path(@user.email_confirmation_token)

    assert_redirected_to root_path
  end

  test "invalid token is rejected" do
    patch email_confirmation_path("not-a-real-token")

    assert_redirected_to root_path
    assert_not @user.reload.confirmed?
  end

  test "create resends the confirmation email to the signed-in user" do
    sign_in_as @user
    post email_confirmations_path

    assert_enqueued_email_with EmailConfirmationsMailer, :confirm, args: [ @user ]
  end

  test "create does nothing for an already-confirmed user" do
    sign_in_as users(:one)
    post email_confirmations_path

    assert_enqueued_emails 0
  end

  test "create requires sign-in" do
    post email_confirmations_path
    assert_redirected_to new_session_path
  end
end
