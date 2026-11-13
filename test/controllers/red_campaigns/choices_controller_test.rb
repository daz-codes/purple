require "test_helper"

class RedCampaigns::ChoicesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @campaign = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
    sign_in_as users(:one)
  end

  test "picking a card updates the builder" do
    post red_campaign_choices_path(@campaign), params: { option_id: target_options(:lookalike).id }, as: :turbo_stream

    assert_response :success
    assert_equal [ target_options(:lookalike) ], @campaign.reload.chosen_options
    assert_select "turbo-stream[target=campaign_builder] template [data-testid=budget]", text: "6 of 9 left"
  end

  test "taking a card back refunds it" do
    @campaign.choose(target_options(:lookalike))
    delete red_campaign_choice_path(@campaign, target_options(:lookalike)), as: :turbo_stream

    assert_response :success
    assert_equal 0, @campaign.reload.budget_spent
  end

  test "a card from another target, or over budget, is refused" do
    post red_campaign_choices_path(@campaign), params: { option_id: 0 }, as: :turbo_stream
    assert_response :unprocessable_content

    %i[ bank_change lookalike sign_in link ].each { |key| @campaign.choose(target_options(key)) }
    post red_campaign_choices_path(@campaign), params: { option_id: target_options(:friday).id }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_select "turbo-stream[target=campaign_notice] template", text: /Not enough budget/
  end
end
