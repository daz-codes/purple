require "test_helper"

# The fixture target's budget is 9. Cards: bank_change (3) or overdue (3); lookalike (3) or spoof (1);
# link (1); sign_in (2); friday (1).
class RedCampaign::BuildableTest < ActiveSupport::TestCase
  setup do
    @campaign = RedCampaign.start(user: users(:one), target: targets(:month_end_target))
  end

  test "starting makes one draft per player and target, with a random token and seed" do
    assert @campaign.draft?
    assert_equal 32, @campaign.token.length
    assert_kind_of Integer, @campaign.seed
    assert_equal @campaign, RedCampaign.start(user: users(:one), target: targets(:month_end_target))
  end

  test "choosing a card spends its cost, and choosing another in the same slot swaps it" do
    @campaign.choose(target_options(:lookalike))
    assert_equal [ 3, 6 ], [ @campaign.spent, @campaign.budget_left ]

    @campaign.choose(target_options(:spoof))
    assert_equal [ target_options(:spoof) ], @campaign.chosen_options
    assert_equal 1, @campaign.reload.spent
  end

  test "a card that would go over budget is refused, and spending it exactly is fine" do
    @campaign.choose(target_options(:bank_change))
    @campaign.choose(target_options(:lookalike))
    @campaign.choose(target_options(:sign_in))
    @campaign.choose(target_options(:link)) # 9: the whole budget

    assert_raises(RedCampaign::Rejected, match: /Not enough budget: that card costs 1 and you'd go 1 over/) do
      @campaign.choose(target_options(:friday))
    end
    assert_equal 9, @campaign.reload.spent
  end

  test "a draft's spend follows the cards as they are now, so a content change is reflected at once" do
    @campaign.choose(target_options(:lookalike))
    @campaign.choose(target_options(:bank_change)) # 6 of 9

    techniques(:lookalike_domain).update!(red_cost: 1)
    assert_equal 4, @campaign.reload.spent

    target_options(:bank_change).destroy!
    assert_equal 1, @campaign.reload.spent
    assert_nothing_raised { @campaign.choose(target_options(:overdue)) } # 1 + 3, well within 9
  end

  test "taking a card back refunds it" do
    @campaign.choose(target_options(:lookalike))
    @campaign.unchoose(target_options(:lookalike))

    assert_empty @campaign.chosen_options
    assert_equal 0, @campaign.spent
  end

  test "cards are listed in slot order, and the campaign knows which slots are still empty" do
    @campaign.choose(target_options(:friday))
    @campaign.choose(target_options(:spoof))

    assert_equal %w[ sender timing ], @campaign.chosen_options.map(&:category)
    assert_equal %w[ pretext lure payload ], @campaign.missing_slots
    assert_not @campaign.complete?
  end

  test "only this target's cards, and only while it's a draft" do
    other = Target.create!(shift: shifts(:site_visit), slug: "other", title: "Other", recon_brief: "x", budget: 5)
    card = other.options.create!(technique: techniques(:malicious_link), key: "x", category: "lure", label: "x", rendered_value: "x")
    assert_raises(RedCampaign::Rejected, match: /isn't for this target/) { @campaign.choose(card) }

    @campaign.update_columns(status: "launched", launched_at: Time.current, score: 0, budget: 9, max_score: 81)
    assert_raises(RedCampaign::Rejected, match: /already been launched/) { @campaign.choose(target_options(:link)) }
  end
end
