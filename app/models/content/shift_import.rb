module Content
  # Validates one shift YAML file and upserts it (and its tasks, messages, links, red flags and
  # hints) by key, deleting children that are no longer in the file. Runs inside the importer's
  # transaction, so any error leaves the database untouched.
  class ShiftImport
    SHIFT_KEYS = %i[ slug title kind difficulty time_budget_minutes position published briefing
                     learning_summary action_costs tasks messages hints ].freeze
    TASK_KEYS = %i[ key title due_at_minute points ].freeze
    MESSAGE_KEYS = %i[ key channel arrives_at_minute legit imitates techniques from_name from_address reply_to
                       to_address subject body_html attachments links verify_result red_flags ].freeze
    LINK_KEYS = %i[ match outcome task landing ].freeze
    ATTACHMENT_KEYS = %i[ name type size outcome ].freeze
    RED_FLAG_KEYS = %i[ key anchor points label explanation ].freeze
    HINT_KEYS = %i[ body penalty_percent ].freeze

    # The landing page each link outcome opens in the in-game browser.
    LANDINGS = {
      "completes_task" => "portal_task", "harmless" => "harmless",
      "bait_landing" => "credential_harvest", "malware" => "malware_download"
    }.freeze
    LEGIT_LINK_OUTCOMES = %w[ completes_task harmless ].freeze
    PHISH_LINK_OUTCOMES = %w[ bait_landing malware harmless ].freeze
    ATTACHMENT_OUTCOMES = %w[ harmless malware ].freeze

    def initialize(node, track:, techniques:)
      @node = node
      @track = track
      @techniques = techniques
    end

    # Validates and saves the shift, returning it.
    def run
      @node.allow_only!(*SHIFT_KEYS)
      expected_slug = File.basename(@node.file, ".yml")
      slug = @node.required(:slug)
      @node.error!("slug \"#{slug}\" must match the file name (#{expected_slug})") unless slug == expected_slug

      @shift = Shift.find_or_initialize_by(slug:)
      @node.saving { @shift.update!(shift_attributes) }

      @tasks = import_tasks
      import_messages
      check_every_task_is_completable
      check_imitations_arrive_first
      import_hints

      @shift
    end

    private
      def shift_attributes
        {
          track: @track,
          title: fictional(@node, :title, @node.required(:title)),
          kind: one_of(@node, :kind, Shift.kinds.keys),
          difficulty: one_of(@node, :difficulty, Shift.difficulties.keys),
          time_budget_minutes: positive(@node, :time_budget_minutes),
          position: @node.optional(:position, Integer, default: 0),
          published: @node.optional(:published, Node::BOOLEAN, default: true),
          briefing: fictional(@node, :briefing, @node.required(:briefing)),
          learning_summary: fictional(@node, :learning_summary, @node.required(:learning_summary)),
          action_costs: @node.optional(:action_costs, Hash, default: {}),
          author_side: "red",
          author_type: "system"
        }
      end

      def time_budget
        @shift.time_budget_minutes
      end

      # --- Tasks ---------------------------------------------------------------------------

      def import_tasks
        tasks = @node.each_item(:tasks) do |task_node|
          task_node.allow_only!(*TASK_KEYS)
          due = positive(task_node, :due_at_minute)
          task_node.error!("due_at_minute (#{due}) is after the shift ends (#{time_budget})") if due > time_budget

          task = @shift.tasks.find_or_initialize_by(key: task_node.required(:key))
          task_node.saving do
            task.update!(title: fictional(task_node, :title, task_node.required(:title)),
                         due_at_minute: due, points: positive(task_node, :points))
          end
          task
        end

        @node.check_unique!("task", tasks.map(&:key))
        @shift.tasks.where.not(id: tasks.map(&:id)).each { |stale| stale.links.destroy_all && stale.destroy! }
        tasks.index_by(&:key)
      end

      # --- Messages ------------------------------------------------------------------------

      def import_messages
        @imitations = []
        messages = @node.each_item(:messages) { |message_node, index| import_message(message_node, index + 1) }

        keys = messages.map(&:key)
        @node.check_unique!("message", keys)
        @node.error!("needs at least one phishing message (legit: false)") if messages.all?(&:legit?)
        @shift.messages.where.not(id: messages.map(&:id)).destroy_all
      end

      def import_message(node, position)
        node.allow_only!(*MESSAGE_KEYS)
        channel = one_of(node, :channel, Message.channels.keys)
        legit = node.required(:legit, Node::BOOLEAN)
        arrives = node.optional(:arrives_at_minute, Integer, default: 0)
        node.error!("arrives_at_minute (#{arrives}) must be from 0 to before the shift ends (#{time_budget})") unless arrives.between?(0, time_budget - 1)

        body = processed_body(node)
        attachments = attachments_for(node)
        message = @shift.messages.find_or_initialize_by(key: node.required(:key))

        node.saving do
          message.update!(
            channel:, legit:, position:, arrives_at_minute: arrives,
            from_name: fictional(node, :from_name, node.required(:from_name)),
            from_address: address(node, :from_address, required: true),
            reply_to: address(node, :reply_to),
            to_address: address(node, :to_address, required: channel == "email"),
            subject: subject_for(node, channel),
            body_html: body.html,
            attachments:,
            verify_result: fictional(node, :verify_result, node.optional(:verify_result))
          )
        end

        note_imitation(node, message)
        import_links(node, message, body.links)
        import_techniques(node, message)
        import_red_flags(node, message, anchors: available_anchors(message, body, attachments))
        message
      end

      def processed_body(node)
        MessageBody.new(node.required(:body_html))
      rescue MessageBody::Invalid => invalid
        node.error!("body_html: #{invalid.message}")
      end

      def subject_for(node, channel)
        subject = node.optional(:subject)
        node.error!("subject is required for emails") if channel == "email" && subject.nil?
        fictional(node, :subject, subject)
      end

      def attachments_for(node)
        node.each_item(:attachments, required: false) do |attachment_node, index|
          attachment_node.allow_only!(*ATTACHMENT_KEYS)
          {
            "id" => "a#{index + 1}",
            "name" => fictional(attachment_node, :name, attachment_node.required(:name)),
            "type" => attachment_node.required(:type),
            "size" => attachment_node.required(:size),
            "outcome" => one_of(attachment_node, :outcome, ATTACHMENT_OUTCOMES)
          }
        end
      end

      # Each <a> in the body must match exactly one link rule, and each rule at least one <a>.
      def import_links(node, message, extracted_links)
        allowed_outcomes = message.legit? ? LEGIT_LINK_OUTCOMES : PHISH_LINK_OUTCOMES
        rules = node.each_item(:links, required: extracted_links.any?) do |rule_node|
          rule_node.allow_only!(*LINK_KEYS)
          outcome = one_of(rule_node, :outcome, allowed_outcomes,
            hint: message.legit? ? "legitimate messages" : "phishing messages")
          { node: rule_node, match: rule_node.required(:match), outcome:, task: task_for(rule_node, outcome),
            landing: landing_for(rule_node, outcome) }
        end

        links = extracted_links.map do |extracted|
          matching = rules.select { |rule| extracted.href.include?(rule[:match]) }
          if matching.size != 1
            node.error!("link #{extracted.key} (#{extracted.href}) matches #{matching.size} link rules; it must match exactly one")
          end
          rule = matching.first

          link = message.links.find_or_initialize_by(key: extracted.key)
          rule[:node].saving do
            link.update!(display_url: extracted.text, actual_url: extracted.href, outcome: rule[:outcome],
                         task: rule[:task], landing_template: rule[:landing])
          end
          link
        end

        rules.each do |rule|
          unless extracted_links.any? { |extracted| extracted.href.include?(rule[:match]) }
            rule[:node].error!("match \"#{rule[:match]}\" doesn't match any link in body_html")
          end
        end
        message.links.where.not(id: links.map(&:id)).destroy_all
      end

      def task_for(rule_node, outcome)
        task_key = rule_node.optional(:task)
        if outcome == "completes_task"
          rule_node.error!("task is required when outcome is completes_task") unless task_key
          @tasks.fetch(task_key) { rule_node.error!("task \"#{task_key}\" isn't in this shift's tasks (#{@tasks.keys.join(", ")})") }
        elsif task_key
          rule_node.error!("task can only be set when outcome is completes_task")
        end
      end

      def landing_for(rule_node, outcome)
        landing = rule_node.optional(:landing, String, default: LANDINGS.fetch(outcome))
        unless landing == LANDINGS.fetch(outcome)
          rule_node.error!("landing for a #{outcome} link must be #{LANDINGS.fetch(outcome)} (got #{landing})")
        end
        landing
      end

      def import_techniques(node, message)
        keys = node.optional(:techniques, Array, default: [])
        if message.legit?
          node.error!("legitimate messages can't have techniques") if keys.any?
        else
          node.error!("phishing messages need at least one technique") if keys.empty?
        end

        node.check_unique!("technique", keys.map(&:to_s))

        techniques = keys.map do |key|
          @techniques.fetch(key.to_s) { node.error!("unknown technique \"#{key}\" (known: #{@techniques.keys.sort.join(", ")})") }
        end
        node.saving { message.techniques = techniques }
      end

      def available_anchors(message, body, attachments)
        anchors = %w[ from ]
        anchors << "to" if message.to_address.present?
        anchors << "reply_to" if message.reply_to.present?
        anchors << "subject" if message.subject.present?
        anchors + body.element_ids + attachments.map { |attachment| attachment["id"] }
      end

      def import_red_flags(node, message, anchors:)
        has_flags = node.optional(:red_flags, Array, default: []).any?
        node.error!("legitimate messages can't have red flags") if message.legit? && has_flags
        node.error!("phishing messages need at least one red flag") if message.phish? && !has_flags

        flags = node.each_item(:red_flags, required: message.phish?) do |flag_node|
          flag_node.allow_only!(*RED_FLAG_KEYS)
          anchor = flag_node.required(:anchor)
          unless anchors.include?(anchor)
            flag_node.error!("anchor \"#{anchor}\" doesn't exist in this message (available: #{anchors.join(", ")})")
          end

          flag = message.red_flags.find_or_initialize_by(key: flag_node.required(:key))
          flag_node.saving do
            flag.update!(anchor:, points: positive(flag_node, :points),
                         label: fictional(flag_node, :label, flag_node.required(:label)),
                         explanation: fictional(flag_node, :explanation, flag_node.required(:explanation)))
          end
          flag
        end

        node.check_unique!("red flag", flags.map(&:key))
        message.red_flags.where.not(id: flags.map(&:id)).destroy_all
      end

      # imitates: the task a phishing message pretends to be about. Only checked here, never stored.
      def note_imitation(node, message)
        task_key = node.optional(:imitates) or return
        node.error!("only phishing messages can imitate a task") if message.legit?
        task = @tasks.fetch(task_key) { node.error!("imitates \"#{task_key}\", which isn't in this shift's tasks (#{@tasks.keys.join(", ")})") }
        @imitations << [ node, message, task ]
      end

      # --- Whole-shift checks and hints ----------------------------------------------------

      def check_every_task_is_completable
        @tasks.each_value do |task|
          completing = Link.joins(:message).where(task:, outcome: "completes_task", messages: { legit: true }).count
          next if completing == 1

          @node.error!("task \"#{task.key}\" must be completable by exactly one link in a legitimate message " \
                       "(found #{completing})")
        end
      end

      # A fake that lands after the player has already done the task with the real message gives
      # itself away, so it must arrive no later than the genuine one.
      def check_imitations_arrive_first
        @imitations.each do |node, message, task|
          genuine = Link.joins(:message).where(task:, outcome: "completes_task").pick("messages.arrives_at_minute")
          next if genuine.nil? || message.arrives_at_minute <= genuine

          node.error!("imitates \"#{task.key}\" but arrives at minute #{message.arrives_at_minute}, after the genuine message " \
                      "(minute #{genuine}): the fake must arrive first, or at the same time")
        end
      end

      def import_hints
        hints = @node.each_item(:hints, required: false) do |hint_node, index|
          hint_node.allow_only!(*HINT_KEYS)
          hint = @shift.hints.find_or_initialize_by(position: index + 1)
          hint_node.saving do
            hint.update!(body: fictional(hint_node, :body, hint_node.required(:body)),
                         penalty_percent: hint_node.optional(:penalty_percent, Integer, default: 20))
          end
          hint
        end
        @shift.hints.where.not(id: hints.map(&:id)).destroy_all
      end

      # --- Field helpers -------------------------------------------------------------------

      def one_of(node, key, allowed, hint: nil)
        value = node.required(key)
        node.error!("#{key} must be one of #{allowed.join(", ")}#{" for #{hint}" if hint} (got #{value})") unless allowed.include?(value)
        value
      end

      def positive(node, key)
        value = node.required(key, Integer)
        node.error!("#{key} must be greater than 0") unless value.positive?
        value
      end

      def address(node, key, required: false)
        value = required ? node.required(key) : node.optional(key)
        return if value.nil?

        unless ReservedNames.reserved_address?(value)
          node.error!("#{key} \"#{value}\" must be a fictional address: an email on a reserved domain, " \
                      "a 07700 900xxx number or an SMS sender ID")
        end
        value
      end

      def fictional(node, key, text)
        node.check_fictional!(key, text)
      end
  end
end
