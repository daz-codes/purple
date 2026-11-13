require "test_helper"

class RedCampaigns::LaunchesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @campaign = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
    sign_in_as users(:one)
  end

  test "launching a full set of cards shows what each bot did" do
    %i[ bank_change spoof link sign_in friday ].each { |key| @campaign.choose(target_options(key)) }
    post red_campaign_launch_path(@campaign)

    assert_redirected_to red_campaign_path(@campaign)
    assert @campaign.reload.launched?

    follow_redirect!
    assert_select "[data-testid=bot-result]", count: 2
    assert_select "[data-testid=campaign-score]", text: @campaign.score.to_s
  end

  test "an unfinished campaign can't be launched" do
    post red_campaign_launch_path(@campaign), as: :turbo_stream

    assert_response :unprocessable_content
    assert @campaign.reload.draft?
  end
end
