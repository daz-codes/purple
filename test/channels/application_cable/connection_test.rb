require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  test "an active session connects as its owner" do
    session = users(:one).sessions.create!
    cookies.signed[:session_id] = session.id
    connect
    assert_equal users(:one), connection.current_user
  end

  test "idle and absolute session expiry also apply to cable connections" do
    [ { updated_at: 15.days.ago }, { created_at: 91.days.ago } ].each do |attributes|
      session = users(:one).sessions.create!(attributes)
      cookies.signed[:session_id] = session.id
      assert_reject_connection { connect }
    end
  end

  test "a revoked session cannot connect" do
    session = users(:one).sessions.create!
    cookies.signed[:session_id] = session.id
    session.destroy!
    assert_reject_connection { connect }
  end
end
