require "test_helper"

class Account::PreferencesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "turning relaxed mode on and off from the account page" do
    get account_path
    assert_response :success
    assert_select "input[type=checkbox][name='user[relaxed_mode]']"

    patch account_preferences_path, params: { user: { relaxed_mode: "1" } }
    assert_redirected_to account_path
    assert users(:one).reload.relaxed_mode?

    patch account_preferences_path, params: { user: { relaxed_mode: "0" } }
    assert_not users(:one).reload.relaxed_mode?
  end

  test "only the relaxed setting can be changed here" do
    patch account_preferences_path, params: { user: { relaxed_mode: "1", admin: "1" } }

    assert_not users(:one).reload.admin?
  end
end
