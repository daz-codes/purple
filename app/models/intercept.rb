# One piece of intercepted traffic in a signals mission: a text (the ciphertext, or a log) or a file (a
# photo, a document), a question, and the flag that answers it.
#
# The flag is stored only as digests (#flag_digests), and a submission is compared with them on the
# server in constant time. The solution, explanation and recipe are for the debrief: none of them, nor
# the key, ever reach the page before the mission is over.
class Intercept < ApplicationRecord
  FILE_TYPES = { ".png" => "image/png", ".pdf" => "application/pdf", ".txt" => "text/plain" }.freeze
  MAX_FILE_BYTES = 256.kilobytes

  belongs_to :mission

  validates :key, presence: true, uniqueness: { scope: :mission_id }
  validates :position, numericality: { only_integer: true }, uniqueness: { scope: :mission_id }
  validates :title, :source, :question, :solution, :explanation, presence: true
  validates :points, numericality: { only_integer: true, greater_than: 0 }
  validates :flag_digests, presence: true
  validates :file_type, inclusion: { in: FILE_TYPES.values }, allow_nil: true
  validate :body_or_file

  # The same normalising for authored flags and submissions: Unicode NFKC, case folded, whitespace
  # collapsed, and punctuation at either end dropped. So "Fuel depot" and " fuel  depot." match.
  def self.normalise(answer)
    answer.to_s.unicode_normalize(:nfkc).downcase(:fold).gsub(/[[:space:]]+/, " ")
      .gsub(/\A[[:punct:][:space:]]+|[[:punct:][:space:]]+\z/, "")
  end

  def self.digest(answer)
    OpenSSL::HMAC.hexdigest("SHA256", flag_secret, normalise(answer))
  end

  def self.flag_secret
    @flag_secret ||= Rails.application.key_generator.generate_key("intercept/flag", 32)
  end

  # Whether a submission is the flag. Compares with every accepted digest, so the time taken doesn't
  # depend on which one matched.
  def flag?(answer)
    return false if self.class.normalise(answer).empty?

    submitted = self.class.digest(answer)
    flag_digests.map { |digest| ActiveSupport::SecurityUtils.secure_compare(digest, submitted) }.any?
  end

  def file?
    file_data.present?
  end

  def image?
    file_type == "image/png"
  end

  # The Workbench steps that turn the text back into the solution, for the debrief.
  def undo_steps
    recipe.present? ? Intercept::Cipher.new(recipe).undo_steps : []
  end

  private
    def body_or_file
      errors.add(:base, "needs a body or a file, not both") if body.nil? == file_data.nil?
    end
end
