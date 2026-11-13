require "test_helper"

class RedCampaignsControllerTest < ActionDispatch::IntegrationTest
  test "starting a campaign needs a signed-in player, and starting twice resumes the draft" do
    post target_campaigns_path(targets(:month_end_target))
    assert_redirected_to new_session_path

    sign_in_as users(:one)
    post target_campaigns_path(targets(:month_end_target))
    campaign = RedCampaign.sole
    assert_redirected_to red_campaign_path(campaign)

    post target_campaigns_path(targets(:month_end_target))
    assert_equal 1, RedCampaign.count
  end

  test "the builder shows every slot's cards, the budget and the email so far" do
    campaign = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
    campaign.choose(target_options(:spoof))
    sign_in_as users(:one)

    get red_campaign_path(campaign)

    assert_response :success
    assert_select "[data-testid=slot-pretext] button", count: 2
    assert_select "[data-testid=budget]", text: "8 of 9 left"
    assert_select "[data-testid=email-preview]", text: /Tidemark Supply <tidemark@freemail.test>/
    assert_select "[data-testid=still-to-pick]", text: /the story, the lure, what's behind it, and the timing/
  end

  test "a campaign can only be seen by its owner" do
    campaign = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
    sign_in_as users(:two)

    get red_campaign_path(campaign)
    assert_response :not_found
  end
end
