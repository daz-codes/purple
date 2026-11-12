class User < ApplicationRecord
  PASSWORD_MIN_LENGTH = 12
  # bcrypt's 72-byte limit, already enforced by has_secure_password. Only used for the form's maxlength.
  PASSWORD_MAX_LENGTH = 72
  DISPLAY_NAME_FORMAT = /\A[a-zA-Z0-9_]{3,20}\z/

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :user_badges, dependent: :destroy
  has_many :badges, through: :user_badges
  has_many :shift_attempts, dependent: :destroy

  # Single-use: the token embeds confirmed_at, so it stops working once used.
  generates_token_for :email_confirmation, expires_in: 24.hours do
    [ email_address, confirmed_at ]
  end

  normalizes :email_address, with: ->(email) { email.strip.downcase }
  normalizes :display_name, with: ->(name) { name.strip }

  validates :email_address, presence: true, uniqueness: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :display_name, presence: true, uniqueness: true,
    format: { with: DISPLAY_NAME_FORMAT, message: "must be 3–20 letters, numbers or underscores" }
  validates :password, length: { minimum: PASSWORD_MIN_LENGTH }, allow_nil: true

  def self.find_by_email_confirmation_token(token)
    find_by_token_for(:email_confirmation, token)
  end

  def email_confirmation_token
    generate_token_for(:email_confirmation)
  end

  def confirmed?
    confirmed_at.present?
  end

  def confirm!
    update!(confirmed_at: Time.current) unless confirmed?
  end

  # Unconfirmed players can play, but progress only counts once they've
  # proved they own their email address.
  def earns_xp?
    confirmed?
  end

  # Sets a new password from the reset form. Unlike a plain update, a blank password is an error
  # (has_secure_password silently ignores an empty string) and a missing confirmation counts as
  # a mismatch rather than skipping the check.
  def reset_password(password:, password_confirmation:)
    if password.blank?
      errors.add(:password, :blank)
      return false
    end

    update(password: password, password_confirmation: password_confirmation.to_s)
  end
end
