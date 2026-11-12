# A social-engineering technique: the shared vocabulary of the Red and Blue sides.
# Mapped to MITRE ATT&CK where an ID exists (timing tricks have none).
class Technique < ApplicationRecord
  ATTACK_ID_FORMAT = /\AT\d{4}(\.\d{3})?\z/

  enum :category, { pretext: "pretext", sender: "sender", lure: "lure", payload: "payload", timing: "timing" },
    prefix: true, validate: true

  has_many :message_techniques, dependent: :restrict_with_exception
  has_many :messages, through: :message_techniques

  validates :key, presence: true, uniqueness: true
  validates :name, :description, :defence_tip, :red_flag_label, presence: true
  validates :attack_id, format: { with: ATTACK_ID_FORMAT }, allow_nil: true
  validates :stealth, numericality: { only_integer: true, in: 1..10 }
  validates :red_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def attack_url
    "https://attack.mitre.org/techniques/#{attack_id.tr(".", "/")}/" if attack_id
  end
end
