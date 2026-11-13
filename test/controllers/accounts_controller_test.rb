require "test_helper"

class AccountsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "shows your details and lists your sessions only" do
    mine = @user.sessions.create!(user_agent: "Firefox on Linux", ip_address: "192.0.2.10")
    someone_else = users(:two).sessions.create!(ip_address: "198.51.100.7")
    sign_in_as @user

    get account_path

    assert_response :success
    assert_select "dd", text: @user.display_name
    assert_select "##{ActionView::RecordIdentifier.dom_id(mine)}"
    assert_select "##{ActionView::RecordIdentifier.dom_id(someone_else)}", count: 0
  end

  test "requires sign-in" do
    get account_path
    assert_redirected_to new_session_path
  end
end
