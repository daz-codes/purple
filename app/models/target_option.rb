# One card Red can pick for a target, in one of the five slots. Each card is a technique, worded for
# this target: rendered_value is the pre-written text it puts into the email (there's no free text, so
# the Workshop can't produce a usable real-world phish). A pretext also sets the subject line.
# relevance (0-3) is how well it matches what the target is really expecting.
class TargetOption < ApplicationRecord
  CATEGORIES = %w[ pretext sender lure payload timing ].freeze

  enum :category, CATEGORIES.index_by(&:itself), prefix: true, validate: true

  belongs_to :target
  belongs_to :technique

  validates :key, presence: true, uniqueness: { scope: :target_id }
  validates :label, :rendered_value, presence: true
  validates :subject, presence: true, if: :category_pretext?
  validates :subject, absence: true, unless: :category_pretext?
  validates :relevance, numericality: { only_integer: true, in: 0..3 }
  validates :extra_cost, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def cost
    technique.red_cost + extra_cost
  end
end
