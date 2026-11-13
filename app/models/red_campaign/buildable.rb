# Building a campaign: one card per slot, within the target's budget. Picking a card in a slot that
# already has one swaps it. While it's a draft, what's been spent is worked out from the cards as they
# are now, so a content import that changes a card's cost (or removes it) is reflected at once. At
# launch the spend is stored with the result.
module RedCampaign::Buildable
  extend ActiveSupport::Concern

  def choose(option)
    with_lock do
      reject "This campaign has already been launched." unless draft?
      reject "That card isn't for this target." unless option.target_id == target_id

      replaced = chosen_options.find { |chosen| chosen.category == option.category }
      spent = spent_on(chosen_options.excluding(replaced) + [ option ])
      reject "Not enough budget: that card costs #{option.cost} and you'd go #{spent - target.budget} over." if spent > target.budget

      update!(chosen_option_ids: chosen_options.excluding(replaced).map(&:id) + [ option.id ])
      @chosen_options = nil
    end
  end

  def unchoose(option)
    with_lock do
      reject "This campaign has already been launched." unless draft?
      return unless chosen_option_ids.include?(option.id)

      update!(chosen_option_ids: chosen_option_ids - [ option.id ])
      @chosen_options = nil
    end
  end

  # The chosen cards, in slot order. A card removed by a later content import drops out.
  def chosen_options
    @chosen_options ||= target.options.includes(:technique).select { |option| option.id.in?(chosen_option_ids) }
      .sort_by { |option| TargetOption::CATEGORIES.index(option.category) }
  end

  def chosen_for(category)
    chosen_options.find { |option| option.category == category.to_s }
  end

  def chosen?(option)
    chosen_option_ids.include?(option.id)
  end

  # What the cards cost: as they are now for a draft, as it was at launch afterwards.
  def spent
    draft? ? spent_on(chosen_options) : budget_spent
  end

  def total_budget
    draft? ? target.budget : budget
  end

  def budget_left
    total_budget - spent
  end

  def missing_slots
    TargetOption::CATEGORIES - chosen_options.map(&:category)
  end

  def complete?
    missing_slots.empty?
  end

  def reload(*)
    @chosen_options = nil
    super
  end

  private
    def spent_on(options)
      options.sum(&:cost)
    end

    def reject(message)
      raise RedCampaign::Rejected, message
    end
end
