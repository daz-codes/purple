# XP and levels, one track for each side. XP is only ever added through #award_xp, which writes the
# ledger entry and the side's running total and level together, so they can't disagree.
#
# Level curve: level 1 at 0 XP, and reaching level n needs 100 * (n - 1)^1.5 XP in total: 100 for
# level 2, 283 for level 3, 520 for level 4, and so on.
module User::Progression
  extend ActiveSupport::Concern

  SIDES = %w[ blue red ].freeze
  LEVEL_STEP = 100

  included do
    has_many :xp_events, -> { order(:occurred_at, :id) }, dependent: :delete_all

    validates :preferred_side, inclusion: { in: SIDES }, allow_nil: true
  end

  class_methods do
    # The total XP a level starts at.
    def xp_for_level(level)
      level <= 1 ? 0 : (LEVEL_STEP * (level - 1)**1.5).ceil
    end

    def level_for(xp)
      level = 1
      level += 1 while xp >= xp_for_level(level + 1)
      level
    end
  end

  # Adds XP to one side. Returns the event, or nil if this source has already earned this kind of XP.
  def award_xp(side:, amount:, reason:, source: nil, at: Time.current)
    transaction do
      lock!
      return if source && xp_events.exists?(reason:, source_type: source.class.polymorphic_name, source_id: source.id)

      event = xp_events.create!(side:, amount:, reason:, source:, occurred_at: at)
      xp = xp(side) + amount
      update!("#{side}_xp" => xp, "#{side}_level" => self.class.level_for(xp), xp_total: blue_xp + red_xp + amount)
      event
    end
  end

  def xp(side)
    public_send(:"#{side}_xp")
  end

  def level(side)
    public_send(:"#{side}_level")
  end

  # How far through the current level a side is, from 0 to 1.
  def level_progress(side)
    floor = self.class.xp_for_level(level(side))
    ceiling = self.class.xp_for_level(level(side) + 1)
    (xp(side) - floor).fdiv(ceiling - floor)
  end

  def xp_to_next_level(side)
    self.class.xp_for_level(level(side) + 1) - xp(side)
  end

  def choose_side(side)
    update!(preferred_side: side)
  end
end
