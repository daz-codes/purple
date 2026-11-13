# A Red's Workshop brief: what Red has learned about one of Blue's companies (the one in the linked
# shift), the budget for the campaign, and the cards Red can pick from.
class Target < ApplicationRecord
  belongs_to :shift
  has_many :options, -> { order(:position, :id) }, class_name: "TargetOption", dependent: :destroy
  has_many :red_campaigns, dependent: :restrict_with_exception

  scope :published, -> { where(published: true) }
  scope :in_order, -> { order(:position, :id) }

  validates :slug, presence: true, uniqueness: true
  validates :title, :recon_brief, presence: true
  validates :budget, numericality: { only_integer: true, greater_than: 0 }

  def to_param
    slug
  end

  def options_for(category)
    options.select { |option| option.category == category.to_s }
  end
end
