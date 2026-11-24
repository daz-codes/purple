require "test_helper"

class User::UnlocksTest < ActiveSupport::TestCase
  def unlocks(user = users(:one)) = User::Unlocks.new(user)

  def finish(mission, user: users(:one))
    MissionAttempt.start(user:, mission:).tap(&:stand_down)
  end

  test "a path that opens always is open, with its first track, to anyone" do
    [ unlocks, unlocks(nil) ].each do |visitor_or_player|
      assert visitor_or_player.open?(paths(:codebreaking))
      assert visitor_or_player.open?(tracks(:encodings))
      assert visitor_or_player.open?(missions(:kettle))
    end
  end

  test "a track opens once enough missions on the track before it are finished" do
    assert_not unlocks.open?(tracks(:ciphers))
    assert_not unlocks.open?(missions(:tea_for_two))
    assert_equal "Finish 1 more mission on Encodings to open this track.", unlocks.opens_when(tracks(:ciphers))

    finish missions(:kettle)
    assert unlocks.open?(tracks(:ciphers))
    assert_nil unlocks.opens_when(tracks(:ciphers))
  end

  test "an attempt that timed out doesn't count as finished" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:kettle))
    travel MissionAttempt::Timed::EXPIRES_AFTER + 1.minute
    attempt.expire_if_stale

    assert attempt.timed_out?
    assert_not unlocks.finished?(missions(:kettle))
    assert_not unlocks.open?(tracks(:ciphers))
  end

  test "a path that opens after some missions counts them on any path" do
    track = Track.create!(path: paths(:break_in), slug: "injection", title: "Injection", description: "x", difficulty: "beginner", published: true)
    Mission.create!(track:, slug: "open-door", title: "Open door", kind: "signals", difficulty: "beginner", par_minutes: 5,
                    published: true, briefing: "x", learning_summary: "x")

    assert_not unlocks.open?(paths(:break_in))
    assert_not unlocks.open?(track)
    assert_equal "Finish 3 more missions on any path to open Break-in.", unlocks.opens_when(paths(:break_in))
    assert_equal "Finish 3 more missions on any path to open Break-in.", unlocks.opens_when(track)

    [ missions(:month_end), missions(:kettle), missions(:daily_drizzle) ].each { |mission| finish mission }
    assert unlocks.open?(paths(:break_in))
    assert unlocks.open?(track)
  end

  test "a path that opens after another path's first track needs every mission on it finished" do
    paths(:break_in).update!(opens: "after_first_track", opens_after_missions: nil, opens_after_path: paths(:phishing))
    assert_equal "Finish the Basics track on Phishing to open Break-in.", unlocks.opens_when(paths(:break_in))

    finish missions(:month_end)
    assert_not unlocks.open?(paths(:break_in))
    finish missions(:site_visit)
    assert unlocks.open?(paths(:break_in))
  end

  test "nothing locks again: a track the player has played stays open whatever the rules say now" do
    finish missions(:kettle)
    MissionAttempt.start(user: users(:one), mission: missions(:tea_for_two))
    tracks(:ciphers).update!(unlock_after: 0)
    missions(:kettle).update!(published: false)
    tracks(:ciphers).update!(unlock_after: 1)

    assert unlocks.open?(tracks(:ciphers))
  end

  test "the daily track is open to everyone, and visitors see what a new player would" do
    assert unlocks(nil).open?(missions(:daily_drizzle))
    assert_not unlocks(nil).open?(tracks(:ciphers))
    assert_not unlocks(nil).finished?(missions(:kettle))
  end
end
