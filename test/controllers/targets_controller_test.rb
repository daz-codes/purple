require "test_helper"

class TargetsControllerTest < ActionDispatch::IntegrationTest
  test "anyone can browse the Workshop and read a recon brief" do
    get targets_path
    assert_response :success
    assert_select "h2", text: "Month-end at Larkhill"

    get target_path(targets(:month_end_target))
    assert_response :success
    assert_select "p", text: /Tidemark's invoice is due this week/
    assert_select "a", text: "Sign in to play"
  end

  test "unpublished targets aren't found" do
    targets(:month_end_target).update!(published: false)

    get target_path(targets(:month_end_target))
    assert_response :not_found
  end
end
