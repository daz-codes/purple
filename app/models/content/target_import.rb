module Content
  # Validates one Red's Workshop target YAML file and upserts it with its cards, by key, deleting cards
  # no longer in the file. Runs inside the importer's transaction.
  #
  #   slug, title, shift (the Blue shift whose company it targets), budget, position, published,
  #   recon_brief, and cards: one list per slot (pretext, sender, lure, payload, timing), each card
  #   { key, technique, label, text, relevance (0-3), extra_cost }, and pretexts also a subject.
  #
  # Every card's text is fictional, and each card's technique must belong to its slot.
  class TargetImport
    TARGET_KEYS = %i[ slug title shift budget position published recon_brief cards ].freeze
    CARD_KEYS = %i[ key technique label subject text relevance extra_cost ].freeze
    MIN_CARDS_PER_SLOT = 2

    def initialize(node, shifts:, techniques:)
      @node = node
      @shifts = shifts
      @techniques = techniques
    end

    def run
      @node.allow_only!(*TARGET_KEYS)
      expected_slug = File.basename(@node.file, ".yml")
      slug = @node.required(:slug)
      @node.error!("slug \"#{slug}\" must match the file name (#{expected_slug})") unless slug == expected_slug

      @target = Target.find_or_initialize_by(slug:)
      @node.saving { @target.update!(target_attributes) }
      import_cards
      check_a_full_set_fits_the_budget
      @target
    end

    private
      def target_attributes
        shift_slug = @node.required(:shift)
        shift = @shifts.find { |candidate| candidate.slug == shift_slug } or
          @node.error!("shift \"#{shift_slug}\" isn't one of the imported shifts (#{@shifts.map(&:slug).sort.join(", ")})")
        budget = @node.required(:budget, Integer)
        @node.error!("budget must be greater than 0") unless budget.positive?

        {
          shift:, budget:,
          title: @node.check_fictional!(:title, @node.required(:title)),
          recon_brief: @node.check_fictional!(:recon_brief, @node.required(:recon_brief)),
          position: @node.optional(:position, Integer, default: 0),
          published: @node.optional(:published, Node::BOOLEAN, default: true)
        }
      end

      def import_cards
        slots = @node.child(:cards)
        slots.allow_only!(*TargetOption::CATEGORIES)
        position = 0
        cards = TargetOption::CATEGORIES.flat_map do |category|
          slot = slots.each_item(category) { |card_node| import_card(card_node, category, position += 1) }
          slots.error!("#{category} needs at least #{MIN_CARDS_PER_SLOT} cards to choose from") if slot.size < MIN_CARDS_PER_SLOT
          slot
        end

        @node.check_unique!("card", cards.map(&:key))
        @target.options.where.not(id: cards.map(&:id)).destroy_all
        @cards = cards
      end

      def import_card(node, category, position)
        node.allow_only!(*CARD_KEYS)
        technique_key = node.required(:technique)
        technique = @techniques.fetch(technique_key) { node.error!("unknown technique \"#{technique_key}\"") }
        unless technique.category == category
          node.error!("technique #{technique_key} is a #{technique.category} technique, so it can't go in the #{category} slot")
        end

        subject = node.optional(:subject)
        node.error!("subject is required for pretexts") if category == "pretext" && subject.nil?
        node.error!("subject is only for pretexts") if category != "pretext" && subject

        relevance = node.optional(:relevance, Integer, default: 0)
        node.error!("relevance must be from 0 to 3") unless relevance.between?(0, 3)

        card = @target.options.find_or_initialize_by(key: node.required(:key))
        node.saving do
          card.update!(category:, technique:, position:, relevance:,
            label: node.check_fictional!(:label, node.required(:label)),
            subject: subject && node.check_fictional!(:subject, subject),
            rendered_value: node.check_fictional!(:text, node.required(:text)),
            extra_cost: node.optional(:extra_cost, Integer, default: 0))
        end
        card
      end

      def check_a_full_set_fits_the_budget
        cheapest = TargetOption::CATEGORIES.sum { |category| @cards.select { |card| card.category == category }.map(&:cost).min }
        return if cheapest <= @target.budget

        @node.error!("the cheapest card in every slot costs #{cheapest} together, over the budget of #{@target.budget}")
      end
  end
end
