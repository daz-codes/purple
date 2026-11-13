require "test_helper"

class SidesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  test "asks which side to try first, and sends the player there" do
    get new_side_path
    assert_response :success
    assert_select "h1", text: "Which side do you want to try first?"

    post side_path, params: { side: "red" }
    assert_redirected_to targets_path
    assert_equal "red", users(:one).reload.preferred_side

    post side_path, params: { side: "blue" }
    assert_redirected_to tracks_path
  end

  test "the dashboard's switcher comes back to the dashboard" do
    post side_path, params: { side: "red", return_to: "dashboard" }

    assert_redirected_to root_path
  end

  test "only blue or red" do
    post side_path, params: { side: "purple" }

    assert_redirected_to new_side_path
    assert_nil users(:one).reload.preferred_side
  end
end
