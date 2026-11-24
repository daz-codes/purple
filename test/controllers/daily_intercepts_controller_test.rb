require "test_helper"

class DailyInterceptsControllerTest < ActionDispatch::IntegrationTest
  test "goes to today's briefing" do
    get daily_intercept_path
    assert_redirected_to mission_path(DailyIntercept.new.mission)
  end

  test "says so when there isn't one" do
    tracks(:daily).update!(published: false)
    get daily_intercept_path
    assert_redirected_to paths_path
  end
end
