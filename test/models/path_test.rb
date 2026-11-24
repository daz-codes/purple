require "test_helper"

class PathTest < ActiveSupport::TestCase
  test "a path opens always, after a number of missions, or after another path's first track" do
    assert paths(:phishing).valid?
    assert paths(:break_in).valid?

    path = paths(:codebreaking)
    path.opens = "after_missions"
    assert_not path.valid?
    path.opens_after_missions = 2
    assert path.valid?

    path.opens = "after_first_track"
    assert_not path.valid?, "a mission count only goes with after_missions"
    path.opens_after_missions = nil
    path.opens_after_path = paths(:phishing)
    assert path.valid?

    path.opens_after_path = path
    assert_not path.valid?
  end

  test "the database holds the opening rules too" do
    assert_raises(ActiveRecord::StatementInvalid) { paths(:phishing).update_columns(opens: "after_missions") }
  end

  test "a path is coming soon until one of its published tracks has a published mission" do
    assert_not paths(:phishing).coming_soon?
    assert paths(:break_in).coming_soon?

    Mission.update_all(published: false)
    assert paths(:phishing).reload.coming_soon?
  end

  test "missions in play order follow the paths, then the tracks, then the missions" do
    later = Track.create!(path: paths(:break_in), slug: "later", title: "Later", description: "x", difficulty: "beginner", published: true)
    mission = missions(:month_end).dup.tap { |copy| copy.update!(slug: "later-mission", track: later) }

    assert_equal [ missions(:month_end), missions(:site_visit), missions(:kettle), missions(:tea_for_two), missions(:daily_drizzle), mission ],
      Mission.in_play_order.to_a
    paths(:break_in).update!(position: 0)
    assert_equal mission, Mission.in_play_order.first
  end

  test "the daily track alone doesn't make a path playable" do
    Mission.where.not(track: tracks(:daily)).update_all(published: false)
    assert paths(:codebreaking).reload.coming_soon?
  end
end
