require "test_helper"

class RedCampaign::LaunchableTest < ActiveSupport::TestCase
  setup do
    @campaign = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
  end

  test "launching assembles and stores the email, runs the bots, and scores the result" do
    choose :bank_change, :spoof, :link, :sign_in, :friday # 8 of 9
    @campaign.launch

    assert @campaign.launched?
    assert_equal [ "New bank details", "Tidemark Supply <tidemark@freemail.test>" ], [ @campaign.rendered_subject, @campaign.rendered_from ]
    assert_equal "<p>Our bank details have changed.</p><p>Pay here: portal.tidemark-billing.example/4471</p>", @campaign.rendered_body_html
    assert_equal %w[ busy_bob careful_carol ], @campaign.results.map { |result| result["bot"] }
    assert_equal RedCampaign.score_for(@campaign.results, 1), @campaign.score
    assert @campaign.scored?
  end

  test "the score is 40 per bot fooled, 15 per near miss, and 1 per unit of budget left" do
    results = [ { "outcome" => "fooled" }, { "outcome" => "near_miss" }, { "outcome" => "reported" }, { "outcome" => "verified" } ]

    assert_equal 40 + 15 + 3, RedCampaign.score_for(results, 3)
  end

  test "the result doesn't change when the content does" do
    choose :bank_change, :spoof, :link, :sign_in, :friday
    @campaign.launch
    stored = [ @campaign.results, @campaign.rendered_body_html, @campaign.score ]

    target_options(:bank_change).update!(rendered_value: "Something else entirely.")
    assert_equal stored, RedCampaign.find(@campaign.id).then { |campaign| [ campaign.results, campaign.rendered_body_html, campaign.score ] }
  end

  test "stars are judged against every bot fooled with the cheapest full set of cards" do
    choose :bank_change, :spoof, :link, :sign_in, :friday
    @campaign.launch

    assert_equal 40 * 2 + 9 - 8, @campaign.max_score
    assert_equal RedCampaign::Launchable::STAR_THRESHOLDS.count { |threshold| @campaign.score >= @campaign.max_score * threshold }, @campaign.stars
  end

  test "a campaign needs every slot filled, and launches once" do
    choose :bank_change, :spoof
    assert_raises(RedCampaign::Rejected, match: /lure, payload, and timing still empty/) { @campaign.launch }

    choose :link, :sign_in, :friday
    @campaign.launch
    assert_raises(RedCampaign::Rejected, match: /already been launched/) { @campaign.launch }
  end

  test "only a confirmed player's first launched campaign at a target is scored" do
    choose :bank_change, :spoof, :link, :sign_in, :friday
    @campaign.launch
    second = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
    second.choose(target_options(:overdue))
    %i[ spoof link sign_in friday ].each { |key| second.choose(target_options(key)) }
    second.launch

    assert @campaign.scored?
    assert_not second.scored?
  end

  private
    def choose(*keys)
      keys.each { |key| @campaign.choose(target_options(key)) }
    end
end
