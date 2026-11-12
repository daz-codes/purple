require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  VALID_PARAMS = { user: { display_name: "new_player", email_address: "new.player@example.com",
                           password: "correct horse battery", password_confirmation: "correct horse battery" } }

  test "new" do
    get new_registration_path
    assert_response :success
  end

  test "create signs the user up, signs them in and sends a confirmation email" do
    assert_difference -> { User.count } => 1, -> { Session.count } => 1 do
      post registration_path, params: VALID_PARAMS
    end

    user = User.find_by!(email_address: "new.player@example.com")
    assert_not user.confirmed?
    assert_enqueued_email_with EmailConfirmationsMailer, :confirm, args: [ user ]
    assert_redirected_to root_path
    assert cookies[:session_id].present?
  end

  test "create with invalid details re-renders the form" do
    assert_no_difference -> { User.count } do
      post registration_path, params: { user: VALID_PARAMS[:user].merge(password_confirmation: "something else") }
    end

    assert_response :unprocessable_entity
    assert_select "#error_explanation"
  end

  test "create cannot set admin" do
    post registration_path, params: { user: VALID_PARAMS[:user].merge(admin: true, confirmed_at: Time.current) }

    user = User.find_by!(email_address: "new.player@example.com")
    assert_not user.admin?
    assert_not user.confirmed?
  end

  test "signed-in users are redirected away" do
    sign_in_as users(:one)
    get new_registration_path
    assert_redirected_to root_path
  end
end
