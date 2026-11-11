require "test_helper"

class UserTest < ActiveSupport::TestCase
  def build_user(**attrs)
    User.new({ email_address: "player@example.com", display_name: "player_1",
               password: "correct horse battery", password_confirmation: "correct horse battery" }.merge(attrs))
  end

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal("downcased@example.com", user.email_address)
  end

  test "valid with good attributes" do
    assert build_user.valid?
  end

  test "requires a well-formed email address" do
    assert_not build_user(email_address: "not-an-email").valid?
  end

  test "email address is unique regardless of case" do
    user = build_user(email_address: users(:one).email_address.upcase)
    assert_not user.valid?
    assert_includes user.errors[:email_address], "has already been taken"
  end

  test "display name must be 3-20 letters, numbers or underscores" do
    assert_not build_user(display_name: "ab").valid?
    assert_not build_user(display_name: "a" * 21).valid?
    assert_not build_user(display_name: "has space").valid?
    assert_not build_user(display_name: "slash/name").valid?
    assert build_user(display_name: "Red_Team_99").valid?
  end

  test "display name is unique regardless of case" do
    user = build_user(display_name: users(:one).display_name.upcase)
    assert_not user.valid?
    assert_includes user.errors[:display_name], "has already been taken"
  end

  test "the database enforces unique display names" do
    duplicate = build_user(display_name: users(:one).display_name)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  test "password must be at least 12 characters" do
    user = build_user(password: "short", password_confirmation: "short")
    assert_not user.valid?
    assert user.errors[:password].any? { |message| message.include?("too short") }
  end

  test "unconfirmed users can play but don't earn XP" do
    assert_not users(:unconfirmed).confirmed?
    assert_not users(:unconfirmed).earns_xp?
    assert users(:one).earns_xp?
  end

  test "confirmation token confirms the user" do
    user = users(:unconfirmed)
    found = User.find_by_email_confirmation_token(user.email_confirmation_token)

    assert_equal user, found
    found.confirm!
    assert user.reload.confirmed?
  end

  test "confirmation token can only be used once" do
    user = users(:unconfirmed)
    token = user.email_confirmation_token
    user.confirm!

    assert_nil User.find_by_email_confirmation_token(token)
  end

  test "confirmation token expires after 24 hours" do
    token = users(:unconfirmed).email_confirmation_token

    travel 25.hours do
      assert_nil User.find_by_email_confirmation_token(token)
    end
  end

  test "confirmation token is invalidated when the email address changes" do
    user = users(:unconfirmed)
    token = user.email_confirmation_token
    user.update!(email_address: "changed@example.com")

    assert_nil User.find_by_email_confirmation_token(token)
  end

  test "confirm! keeps the original confirmation time" do
    user = users(:one)
    assert_no_changes -> { user.reload.confirmed_at } do
      user.confirm!
    end
  end

  test "reset_password sets a new password" do
    user = users(:one)
    assert user.reset_password(password: "a brand new passphrase", password_confirmation: "a brand new passphrase")
    assert user.reload.authenticate("a brand new passphrase")
  end

  test "reset_password rejects a blank password" do
    user = users(:one)
    assert_no_changes -> { user.reload.password_digest } do
      assert_not user.reset_password(password: "", password_confirmation: "")
    end
    assert_includes user.errors[:password], "can't be blank"
  end

  test "reset_password treats a missing confirmation as a mismatch" do
    user = users(:one)
    assert_no_changes -> { user.reload.password_digest } do
      assert_not user.reset_password(password: "a brand new passphrase", password_confirmation: nil)
    end
    assert user.errors[:password_confirmation].any?
  end

  test "a long password gets a single too-long error" do
    user = User.new(password: "a" * 73)
    user.valid?
    assert_equal 1, user.errors[:password].size
  end
end
