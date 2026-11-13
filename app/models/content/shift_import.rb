module Content
  # Validates one shift YAML file and upserts it (and its messages, links, red flags and hints) by key, deleting children that are no longer in the file. Runs inside the importer's
  # transaction, so any error leaves the database untouched.
  class ShiftImport
    SHIFT_KEYS = %i[ slug title kind difficulty par_minutes position published briefing
                     learning_summary messages hints ].freeze
    MESSAGE_KEYS = %i[ key channel arrives legit expects points urgent_within_minutes techniques from_name
                       from_address reply_to to_address subject body_html attachments replies links verify_result
                       red_flags ].freeze
    ARRIVAL_KEYS = %i[ after_handled after ].freeze
    LINK_KEYS = %i[ match outcome landing action ].freeze
    ATTACHMENT_KEYS = %i[ name type size outcome ].freeze
    REPLY_KEYS = %i[ text outcome response ].freeze
    # An inbox shift is played in an email client and a messages shift on a phone, and each only shows
    # its own kind of message.
    CHANNELS = { "inbox" => %w[ email ], "messages" => %w[ sms chat ] }.freeze
    MAX_REPLIES = 4
    # safe: fine. poor: answers a genuine message badly, so it doesn't count as replying. compromise:
    # hands a phisher what they asked for. verify: checks with someone trusted first.
    REPLY_OUTCOMES = %w[ safe poor compromise verify ].freeze
    RED_FLAG_KEYS = %i[ key anchor quote in points label explanation ].freeze
    HINT_KEYS = %i[ body penalty_percent ].freeze

    # The landing page each link outcome opens in the in-game browser.
    LANDINGS = {
      "portal" => "portal", "harmless" => "harmless",
      "bait_landing" => "credential_harvest", "malware" => "malware_download"
    }.freeze
    LEGIT_LINK_OUTCOMES = %w[ portal harmless ].freeze
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

      import_messages
      check_every_message_can_arrive
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
          par_minutes: positive(@node, :par_minutes),
          position: @node.optional(:position, Integer, default: 0),
          published: @node.optional(:published, Node::BOOLEAN, default: true),
          briefing: fictional(@node, :briefing, @node.required(:briefing)),
          learning_summary: fictional(@node, :learning_summary, @node.required(:learning_summary)),
          author_side: "red",
          author_type: "system"
        }
      end

      # --- Messages ------------------------------------------------------------------------

      def import_messages
        messages = @node.each_item(:messages) { |message_node, index| import_message(message_node, index + 1) }

        keys = messages.map(&:key)
        @node.check_unique!("message", keys)
        @node.error!("needs at least one phishing message (legit: false)") if messages.all?(&:legit?)
        @shift.messages.where.not(id: messages.map(&:id)).destroy_all
        @messages = messages
      end

      def import_message(node, position)
        node.allow_only!(*MESSAGE_KEYS)
        channel = one_of(node, :channel, CHANNELS.fetch(@shift.kind), hint: "#{@shift.kind} shifts")
        legit = node.required(:legit, Node::BOOLEAN)
        arrival = arrival_for(node)
        expectation = expectation_for(node, legit:)

        body = processed_body(node)
        attachments = attachments_for(node)
        node.error!("attachments are only for emails") if attachments.any? && channel != "email"
        replies = replies_for(node, channel:, legit:)
        message = @shift.messages.find_or_initialize_by(key: node.required(:key))

        node.saving do
          message.update!(
            channel:, legit:, position:, **arrival, **expectation,
            from_name: fictional(node, :from_name, node.required(:from_name)),
            from_address: address(node, :from_address, required: true),
            reply_to: address(node, :reply_to),
            to_address: address(node, :to_address, required: channel == "email"),
            subject: subject_for(node, channel),
            body_html: body.html,
            attachments:,
            replies:,
            verify_result: fictional(node, :verify_result, node.optional(:verify_result))
          )
        end

        import_links(node, message, body.links)
        check_expectation_can_be_met(node, message)
        import_techniques(node, message)
        import_red_flags(node, message)
        message
      end

      # arrives: start (the default), { after_handled: 2 } (once any 2 messages have been dealt with),
      # or { after: other_key } (once that message has been dealt with). Checked across the whole shift
      # in check_every_message_can_arrive.
      def arrival_for(node)
        value = node.optional(:arrives, Object, default: "start")
        return { arrives_after_handled: nil, arrives_after: nil } if value == "start"
        node.error!("arrives must be start, { after_handled: N } or { after: message_key } (got #{value.inspect})") unless value.is_a?(Hash)

        arrival = node.child(:arrives)
        arrival.allow_only!(*ARRIVAL_KEYS)
        arrival.error!("give exactly one of after_handled or after") unless value.size == 1

        if value.key?("after_handled")
          { arrives_after_handled: positive(arrival, :after_handled), arrives_after: nil }
        else
          { arrives_after_handled: nil, arrives_after: arrival.required(:after) }
        end
      end

      # What a genuine message expects, and what it's worth. A phish always expects a report, which is
      # scored the same for every phish, so it sets none of these.
      def expectation_for(node, legit:)
        if legit
          urgent = (positive(node, :urgent_within_minutes) unless node.optional(:urgent_within_minutes, Object).nil?)
          { expects: one_of(node, :expects, Message.expects.keys), points: positive(node, :points), urgent_within_minutes: urgent }
        else
          %i[ expects points urgent_within_minutes ].each do |key|
            node.error!("#{key} is only for genuine messages: a phish always expects a report") unless node.optional(key, Object).nil?
          end
          { expects: nil, points: 0, urgent_within_minutes: nil }
        end
      end

      # A message that expects a reply must offer one that isn't poor, and one that expects an action
      # must have exactly one portal link to do it on. Portal links are only for those.
      def check_expectation_can_be_met(node, message)
        portals = message.links.count(&:outcome_portal?)
        if message.expects_act?
          node.error!("expects: act needs exactly one portal link to act on (found #{portals})") unless portals == 1
        elsif portals.positive?
          node.error!("portal links are only for messages that expect: act")
        end

        if message.expects_reply? && message.replies.none? { |reply| reply["outcome"].in?(%w[ safe verify ]) }
          node.error!("expects: reply needs at least one reply that isn't poor")
        end
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

      # Canned replies, for texts and chats only. Each gets a neutral id (r1, r2…); its outcome stays on
      # the server. Only a phishing message can have a reply that hands something over.
      def replies_for(node, channel:, legit:)
        replies = node.each_item(:replies, required: false) do |reply_node, index|
          reply_node.allow_only!(*REPLY_KEYS)
          outcome = one_of(reply_node, :outcome, legit ? REPLY_OUTCOMES - %w[ compromise ] : REPLY_OUTCOMES - %w[ poor ],
            hint: legit ? "legitimate messages" : "phishing messages")
          {
            "id" => "r#{index + 1}",
            "text" => fictional(reply_node, :text, reply_node.required(:text)),
            "outcome" => outcome,
            "response" => fictional(reply_node, :response, reply_node.optional(:response))
          }.compact
        end
        return replies if replies.empty?

        node.error!("replies are only for sms and chat messages") if channel == "email"
        node.error!("replies must have from 2 to #{MAX_REPLIES} options") unless replies.size.between?(2, MAX_REPLIES)
        node.error!("each reply needs different text") if replies.map { |reply| reply["text"] }.uniq.size < replies.size
        replies
      end

      # Each <a> in the body must match exactly one link rule, and each rule at least one <a>.
      def import_links(node, message, extracted_links)
        allowed_outcomes = message.legit? ? LEGIT_LINK_OUTCOMES : PHISH_LINK_OUTCOMES
        rules = node.each_item(:links, required: extracted_links.any?) do |rule_node|
          rule_node.allow_only!(*LINK_KEYS)
          outcome = one_of(rule_node, :outcome, allowed_outcomes,
            hint: message.legit? ? "legitimate messages" : "phishing messages")
          { node: rule_node, match: rule_node.required(:match), outcome:, portal_action: portal_action_for(rule_node, outcome),
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
                         portal_action: rule[:portal_action], landing_template: rule[:landing])
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

      # The button on a portal page: what the player does there ("Confirm the delivery slot").
      def portal_action_for(rule_node, outcome)
        action = rule_node.optional(:action)
        if outcome == "portal"
          rule_node.error!("action is required when outcome is portal (the button on the portal page)") unless action
          fictional(rule_node, :action, action)
        elsif action
          rule_node.error!("action can only be set when outcome is portal")
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


      def import_red_flags(node, message)
        has_flags = node.optional(:red_flags, Array, default: []).any?
        node.error!("legitimate messages can't have red flags") if message.legit? && has_flags
        node.error!("phishing messages need at least one red flag") if message.phish? && !has_flags

        flags = node.each_item(:red_flags, required: message.phish?) do |flag_node|
          flag_node.allow_only!(*RED_FLAG_KEYS)
          flag = message.red_flags.find_or_initialize_by(key: flag_node.required(:key))
          flag_node.saving do
            flag.update!(**red_flag_target(flag_node, message), points: positive(flag_node, :points),
                         label: fictional(flag_node, :label, flag_node.required(:label)),
                         explanation: fictional(flag_node, :explanation, flag_node.required(:explanation)))
          end
          flag
        end

        node.check_unique!("red flag", flags.map(&:key))
        message.red_flags.where.not(id: flags.map(&:id)).destroy_all
      end

      # Either anchor: a whole part (from, reply_to, to, subject, l1, a1), or quote: a phrase in the body,
      # found exactly once (in the paragraph named by in:, if given). Body text is always flagged by
      # quote, so a red flag never covers a whole paragraph.
      def red_flag_target(flag_node, message)
        anchor = flag_node.optional(:anchor)
        quote = flag_node.optional(:quote)
        flag_node.error!("give either anchor (a header, link or attachment) or quote (a phrase in the body), not both") if anchor && quote
        flag_node.error!("needs an anchor (a header, link or attachment) or a quote (a phrase in the body)") unless anchor || quote

        if anchor
          unless message.whole_anchors.include?(anchor)
            hint = " Body text is flagged with quote: \"the exact words\"." if anchor.match?(/\Ap\d+/)
            flag_node.error!("anchor \"#{anchor}\" doesn't exist in this message (available: #{message.whole_anchors.join(", ")}).#{hint}")
          end
          return { anchor:, quote: nil, quote_start: nil, quote_end: nil }
        end

        quote = fictional(flag_node, :quote, quote)
        within = flag_node.optional(:in)
        paragraphs = message.paragraphs.values
        if within
          paragraphs = paragraphs.select { |paragraph| paragraph.anchor == within }
          flag_node.error!("in: \"#{within}\" isn't a paragraph of this message (#{message.paragraphs.keys.join(", ")})") if paragraphs.empty?
        end
        found = paragraphs.flat_map { |paragraph| occurrences(paragraph.text, quote).map { |start| [ paragraph, start ] } }
        unless found.size == 1
          flag_node.error!("quote \"#{quote}\" must appear exactly once#{" in #{within}" if within} (found #{found.size}); " \
                           "quote more words, or say which paragraph with in:")
        end

        paragraph, start = found.first
        { anchor: paragraph.anchor, quote:, quote_start: start, quote_end: start + quote.length }
      end

      def occurrences(text, quote)
        starts = []
        index = -1
        starts << index while (index = text.index(quote, index + 1))
        starts
      end

      # --- Whole-shift checks and hints ----------------------------------------------------

      # Every message must be able to arrive: each after: names another message in the shift, and dealing
      # with everything that has arrived must eventually bring the rest. This rules out loops (a after b,
      # b after a) and after_handled counts the shift can't reach.
      def check_every_message_can_arrive
        keys = @messages.map(&:key)
        @messages.each do |message|
          next if message.arrives_after.nil? || (keys.include?(message.arrives_after) && message.arrives_after != message.key)

          @node.error!("message \"#{message.key}\" arrives after \"#{message.arrives_after}\", which isn't another message in this shift")
        end
        @node.error!("at least one message must arrive at the start") if @messages.none?(&:arrives_at_start?)

        stuck = keys - ShiftAttempt::Arrivals.reachable(@messages)
        return if stuck.empty?

        @node.error!("#{stuck.join(", ")} can never arrive: dealing with every other message doesn't bring " \
                     "#{stuck.one? ? "it" : "them"} (check after_handled counts and after: loops)")
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
