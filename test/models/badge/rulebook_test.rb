require "test_helper"

class Badge::RulebookTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "a perfect shift earns First Catch, Eagle Eye, Clean Shift and Productive Paranoid" do
    assert_equal %w[ first_catch eagle_eye clean_shift productive_paranoid ], earned(perfect_shift)
  end

  test "reporting a phish but missing a red flag earns First Catch only" do
    attempt = play { |a| a.archive(messages(:newsletter)); a.flag(messages(:fake_invoice), "from"); a.report(messages(:fake_invoice)) }

    assert_equal %w[ first_catch ], earned(attempt)
  end

  test "Eagle Eye needs no hints" do
    attempt = perfect_shift { |a| a.use_hint }

    assert_not_includes earned(attempt), "eagle_eye"
    assert_includes earned(attempt), "productive_paranoid"
  end

  test "Productive Paranoid needs every genuine message handled as it needed" do
    attempt = play do |a|
      a.archive(messages(:newsletter))
      a.report(messages(:fake_invoice))
      a.archive(messages(:real_invoice)) # without approving it
      a.archive(messages(:supplier_thanks))
    end

    assert_not_includes earned(attempt), "productive_paranoid"
  end

  test "Near Miss Ninja is three bait pages closed without signing in, across shifts" do
    near_miss = ->(a) { a.archive(messages(:newsletter)); a.visit(links(:fake_invoice_link)); a.close_tab }

    second = 2.times.map { play(&near_miss) }.last
    assert_not_includes earned(second), "near_miss_ninja"
    assert_includes earned(play(&near_miss)), "near_miss_ninja"
  end

  test "Seven-Day Streak" do
    @user.update!(current_streak: 7, longest_streak: 7)

    assert_includes earned(play(&:clock_off)), "seven_day_streak"
  end

  test "Fooled Carol, and Budget Hacker for three stars with half the budget left" do
    campaign = launched_campaign(results: [ { "bot" => "careful_carol", "outcome" => "fooled" }, { "bot" => "busy_bob", "outcome" => "fooled" } ],
      score: 80 + 5, budget_spent: 4, max_score: 85)

    assert_equal 3, campaign.stars
    assert_equal %w[ fooled_carol budget_hacker ], earned(campaign)

    spendthrift = launched_campaign(results: [ { "bot" => "careful_carol", "outcome" => "reported" } ], score: 81, budget_spent: 8, max_score: 81)
    assert_empty earned(spendthrift)
  end

  test "Purple Belt is three stars on a shift and on the Workshop target that attacks the same company" do
    attempt = perfect_shift
    assert_not_includes earned(attempt), "purple_belt"

    campaign = launched_campaign(results: [ { "bot" => "careful_carol", "outcome" => "fooled" }, { "bot" => "busy_bob", "outcome" => "fooled" } ],
      score: 85, budget_spent: 4, max_score: 85)
    assert_includes earned(campaign), "purple_belt"
    assert_includes earned(attempt), "purple_belt"
  end

  private
    def earned(source)
      Badge::Rulebook.new(@user, source).earned_keys
    end

    def play
      attempt = ShiftAttempt.start(user: @user, shift: shifts(:month_end))
      yield attempt
      attempt.clock_off if attempt.reload.open?
      attempt.reload
    end

    def perfect_shift
      play do |a|
        yield a if block_given?
        a.visit(links(:real_invoice_link))
        a.use_portal
        a.archive(messages(:newsletter))
        a.flag(messages(:fake_invoice), "from")
        a.flag(messages(:fake_invoice), "p1", from: 0, to: 16)
        a.report(messages(:fake_invoice))
        a.archive(messages(:real_invoice))
        a.archive(messages(:supplier_thanks))
      end
    end

    def launched_campaign(results:, score:, budget_spent:, max_score:)
      RedCampaign.create!(user: @user, target: targets(:month_end_target), status: "launched", launched_at: Time.current,
        results:, score:, budget_spent:, budget: 9, max_score:)
    end
end
