module Content
  # Validates one shift YAML file and upserts it (and its messages, links, red flags and hints) by key, deleting children that are no longer in the file. Runs inside the importer's
  # transaction, so any error leaves the database untouched.
  class ShiftImport
    SHIFT_KEYS = %i[ slug title kind difficulty par_minutes position published briefing
                     learning_summary persona directory messages hints ].freeze
    PERSONA_KEYS = %i[ name role staff_prefix security_question ].freeze
    DIRECTORY_KEYS = %i[ name team contact ].freeze
    MESSAGE_KEYS = %i[ key channel arrives legit imitates expects points urgent_within_minutes techniques from_name
                       from_address reply_to to_address subject body_html attachments replies links verify_result
                       red_flags answer_in needs wants details share_response ].freeze
    DETAIL_KEYS = %i[ key label quote in sensitivity red_use ].freeze
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
    REPLY_OUTCOMES = %w[ safe poor compromise verify ask_why ].freeze
    RED_FLAG_KEYS = %i[ key anchor quote in points label explanation contradicts ].freeze
    # answer_in: and contradicts: point at another message in the shift and quote the words that matter.
    STORY_LINK_KEYS = %i[ message quote ].freeze
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
      check_story_links
      check_imitations_arrive_with_their_genuine_message
      check_phishes_have_follow_ups_too
      check_private_details
      import_hints
      check_lazy_play_doesnt_pay

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
          persona: persona_profile,
          directory: directory_entries,
          author_side: "red",
          author_type: "system"
        }
      end

      # --- Who the player is -----------------------------------------------------------------

      # The persona card's fixed part: name, role, staff-number prefix and an in-world security question
      # (answered with a name, as ShiftAttempt::Persona generates them). The details themselves are
      # generated for each attempt.
      def persona_profile
        return {} unless @node.key?(:persona)

        persona = @node.child(:persona)
        persona.allow_only!(*PERSONA_KEYS)
        prefix = persona.required(:staff_prefix)
        persona.error!("staff_prefix must be 2-3 capital letters, like LH") unless prefix.match?(/\A[A-Z]{2,3}\z/)
        question = fictional(persona, :security_question, persona.required(:security_question))
        persona.error!("security_question must be a question (end with ?)") unless question.end_with?("?")

        { "name" => fictional(persona, :name, persona.required(:name)), "role" => fictional(persona, :role, persona.required(:role)),
          "staff_prefix" => prefix, "security_question" => question }
      end

      # Who the player can check with, and how: an extension or a portal, never an email address, so the
      # directory never replaces checking a sender.
      def directory_entries
        @node.each_item(:directory, required: false) do |entry|
          entry.allow_only!(*DIRECTORY_KEYS)
          contact = fictional(entry, :contact, entry.required(:contact))
          entry.error!("contact is how to reach them (an extension or a portal), not an email address") if contact.include?("@")

          { "name" => fictional(entry, :name, entry.required(:name)), "team" => entry.optional(:team)&.then { |team| fictional(entry, :team, team) },
            "contact" => contact }.compact
        end
      end

      # --- Messages ------------------------------------------------------------------------

      def import_messages
        @imitations = {}
        @story_links = []
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
        answer_in = answer_in_for(node, legit:, expectation:, replies:)
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
            verify_result: fictional(node, :verify_result, node.optional(:verify_result)),
            answer_in_key: answer_in&.dig(:key), answer_in_quote: answer_in&.dig(:quote),
            needs: detail_keys(node, :needs, allowed: legit, hint: "a phish wants details: use wants:"),
            wants: detail_keys(node, :wants, allowed: !legit, hint: "a genuine message needs details: use needs:"),
            share_response: fictional(node, :share_response, node.optional(:share_response))
          )
        end
        import_details(node, message)
        (@message_nodes ||= {})[message.key] = node
        @story_links << answer_in.merge(dependent: message) if answer_in

        note_imitation(node, message)
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

      # Canned replies. Each gets a neutral id (r1, r2…); its outcome stays on
      # the server. Only a phishing message can have a reply that hands something over.
      def replies_for(node, channel:, legit:)
        replies = node.each_item(:replies, required: false) do |reply_node, index|
          reply_node.allow_only!(*REPLY_KEYS)
          outcome = one_of(reply_node, :outcome, legit ? REPLY_OUTCOMES - %w[ compromise ] : REPLY_OUTCOMES - %w[ poor ],
            hint: legit ? "legitimate messages" : "phishing messages")
          reply_node.error!("an ask_why reply needs a response: the sender's answer") if outcome == "ask_why" && reply_node.optional(:response).nil?
          {
            "id" => "r#{index + 1}",
            "text" => fictional(reply_node, :text, reply_node.required(:text)),
            "outcome" => outcome,
            "response" => fictional(reply_node, :response, reply_node.optional(:response))
          }.compact
        end
        return replies if replies.empty?

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
          contradicts = story_link(flag_node, :contradicts)
          flag_node.saving do
            flag.update!(**red_flag_target(flag_node, message), points: positive(flag_node, :points),
                         label: fictional(flag_node, :label, flag_node.required(:label)),
                         explanation: fictional(flag_node, :explanation, flag_node.required(:explanation)),
                         contradicts_key: contradicts&.dig(:key), contradicts_quote: contradicts&.dig(:quote))
          end
          @story_links << contradicts.merge(dependent: message) if contradicts
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

        quote = fictional(flag_node, :quote, Message::Paragraph.normalize(quote))
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
        unless paragraph.sentence_containing(start, start + quote.length)
          flag_node.error!("quote \"#{quote}\" crosses from one sentence into the next; quote words from a single sentence")
        end
        { anchor: paragraph.anchor, quote:, quote_start: start, quote_end: start + quote.length }
      end

      def occurrences(text, quote)
        starts = []
        index = -1
        starts << index while (index = text.index(quote, index + 1))
        starts
      end

      # --- Private details -------------------------------------------------------------------

      def detail_keys(node, key, allowed:, hint:)
        keys = node.optional(key, Array, default: []).map(&:to_s)
        node.error!("#{key} isn't allowed here: #{hint}") if keys.any? && !allowed
        node.check_unique!(key.to_s.singularize, keys)
        keys
      end

      # details: [{ key: wire_codeword, label: "Payment codeword", quote: "BLUEBELL", sensitivity: secret }]:
      # private details the player can learn from this message, quoted in its text like a red flag.
      def import_details(node, message)
        details = node.each_item(:details, required: false) do |detail_node|
          detail_node.allow_only!(*DETAIL_KEYS)
          key = detail_node.required(:key)
          detail_node.error!("key \"#{key}\" is a persona card detail; learned details need their own keys") if key.in?(Shift::Detail::CARD_KEYS)
          target = red_flag_target(detail_node, message)
          detail_node.error!("a detail is quoted from the message's text: give quote:, not anchor:") unless target[:quote]

          { "key" => key, "label" => fictional(detail_node, :label, detail_node.required(:label)),
            "sensitivity" => one_of(detail_node, :sensitivity, Shift::Detail::SENSITIVITIES - %w[ never ]),
            "red_use" => detail_node.optional(:red_use)&.then { |text| fictional(detail_node, :red_use, text) },
            "anchor" => target[:anchor], "quote" => target[:quote], "quote_start" => target[:quote_start], "quote_end" => target[:quote_end] }.compact
        end
        node.saving { message.update!(details:) }
      end

      # The rules that keep sharing honest:
      # - every detail asked for exists, and a learned one is always in the inbox before anything asks;
      # - a genuine message can only ask for a secret (or the MFA code) on its portal page, never by
      #   reply, so "secrets go into the system, never into a message" is always true;
      # - each way of asking offers somewhere to answer: replies (with the "Send details" box) or a page;
      # - a message that asks for details by reply offers "Why do you need this?" (outcome ask_why);
      # - within the shift, every internal detail a phish wants is needed by a genuine message, and the
      #   other way round, so being asked for one never says who's asking.
      def check_private_details
        learned = @messages.flat_map { |message| message.learned_details.map { |detail| [ detail, message ] } }
        @node.check_unique!("learned detail", learned.map { |detail, _| detail.key })
        catalogue = (Shift::Detail::CARD + learned.map(&:first)).index_by(&:key)

        @messages.each do |message|
          node = message_node(message)
          asks = message.needs + message.wants
          asks.each do |key|
            detail = catalogue[key] or node.error!("unknown detail \"#{key}\" (known: #{catalogue.keys.sort.join(", ")})")
            next if detail.card?

            source = learned.find { |candidate, _| candidate.key == key }.last
            node.error!("#{message.key} asks for #{key}, which it holds itself") if source == message
            unless always_arrives_after?(message, source)
              node.error!("#{message.key} could arrive before #{source.key}, where #{key} is learned: #{source.key} must arrive " \
                          "at the start, or #{message.key} after it")
            end
          end
          next if asks.empty?

          if message.legit?
            page_only = message.needs.select { |key| catalogue[key].page_only? }
            if page_only.any? && !message.expects_act?
              node.error!("#{page_only.join(", ")} can only be needed on a portal page (expects: act): secrets never go in a message")
            end
            node.error!("a message that needs details must expect act or reply") if message.expects_archive?
            node.error!("needs details by reply, so it needs replies (the Send details box sits with them)") if message.expects_reply? && message.replies.empty?
          elsif message.replies.empty? && message.links.none? { |link| link.landing_template == "credential_harvest" }
            node.error!("wants details, so it needs replies or a lookalike sign-in link to give them on")
          end

          asks_ask_why = message.replies.count { |reply| reply["outcome"] == "ask_why" }
          if message.replies.any? && asks_ask_why != 1
            node.error!("asks for details and has replies, so it needs exactly one \"Why do you need this?\" reply (outcome: ask_why)")
          end
        end

        @messages.each do |message|
          next if message.needs.any? || message.wants.any?
          message_node(message).error!("only a message that asks for details can offer an ask_why reply") if message.ask_why_reply
        end

        internal = ->(keys) { keys.select { |key| catalogue[key]&.sensitivity == "internal" }.to_set }
        needed = internal.(@messages.select(&:legit?).flat_map(&:needs))
        wanted = internal.(@messages.select(&:phish?).flat_map(&:wants))
        return if needed == wanted

        @node.error!("internal details must be asked for by both sides, so being asked never says who's asking: " \
                     "needed by genuine messages only: #{(needed - wanted).to_a.sort.join(", ").presence || "none"}; " \
                     "wanted by phishes only: #{(wanted - needed).to_a.sort.join(", ").presence || "none"}")
      end

      def message_node(message)
        @message_nodes.fetch(message.key)
      end

      # --- Read it, you'll need it later ----------------------------------------------------

      # answer_in: { message: hr_onboarding, quote: "Room 4B" }: this message asks a question, and the
      # right answer was in that earlier message. Only for a genuine message that expects a reply, with a
      # wrong (poor) answer among its replies, so getting it wrong costs something.
      def answer_in_for(node, legit:, expectation:, replies:)
        return unless node.key?(:answer_in)

        node.error!("answer_in is only for genuine messages that expect a reply") unless legit && expectation[:expects] == "reply"
        node.error!("answer_in needs a wrong answer among the replies (outcome: poor)") if replies.none? { |reply| reply["outcome"] == "poor" }
        story_link(node, :answer_in)
      end

      # { message: key, quote: "the words" }, checked against the other message once the whole shift is
      # imported (check_story_links).
      def story_link(node, key)
        return unless node.key?(key)
        node.error!("#{key} must be { message: other_key, quote: \"the words\" }") unless node.optional(key, Object).is_a?(Hash)

        link = node.child(key)
        link.allow_only!(*STORY_LINK_KEYS)
        { key: link.required(:message), quote: fictional(link, :quote, Message::Paragraph.normalize(link.required(:quote))),
          kind: key, node: link }
      end

      # Each answer_in and contradicts names another message in the shift whose text holds its quote
      # exactly once, and that message is always in the inbox before the one that relies on it. The truth
      # a phish contradicts comes from a genuine message. An answer may only be in a phish if the question
      # arrives last, once every decision has been made, so asking it gives nothing away.
      def check_story_links
        @story_links.each do |link|
          node, dependent = link[:node], link[:dependent]
          source = @messages.find { |message| message.key == link[:key] }
          node.error!("message \"#{link[:key]}\" isn't another message in this shift") if source.nil? || source == dependent
          node.error!("contradicts must point at a genuine message: the truth comes from the real company") if link[:kind] == :contradicts && source.phish?

          found = source.paragraphs.values.sum { |paragraph| occurrences(paragraph.text, link[:quote]).size }
          node.error!("quote \"#{link[:quote]}\" must appear exactly once in #{source.key} (found #{found})") unless found == 1

          if source.phish? && !arrives_last?(dependent)
            node.error!("the answer is in a phish, so #{dependent.key} must arrive last " \
                        "(arrives: { after_handled: #{@messages.size - 1} }), once every decision has been made")
          elsif !always_arrives_after?(dependent, source)
            node.error!("#{dependent.key} could arrive before #{source.key}: #{source.key} must arrive at the start, or " \
                        "#{dependent.key} must arrive after: it (directly or through other after: triggers)")
          end
        end
      end

      def arrives_last?(message)
        message.arrives_after_handled.to_i >= @messages.size - 1
      end

      # Whenever dependent is in the inbox, source is too.
      def always_arrives_after?(dependent, source)
        return true if source.arrives_at_start? || arrives_last?(dependent)

        current = dependent
        seen = []
        while current&.arrives_after && seen.exclude?(current.key)
          return true if current.arrives_after == source.key

          seen << current.key
          current = @messages.find { |message| message.key == current.arrives_after }
        end
        false
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

      # imitates: the genuine message a phish copies. Only checked here, never stored.
      def note_imitation(node, message)
        key = node.optional(:imitates) or return
        node.error!("only phishing messages can imitate another message") if message.legit?
        @imitations[message] = [ node, key ]
      end

      # A fake never arrives after the genuine message it imitates: it arrives at the start, or on exactly
      # the same trigger. Otherwise the player could act on the real one first and spot the fake as a
      # duplicate, instead of having to decide between them.
      def check_imitations_arrive_with_their_genuine_message
        @imitations.each do |fake, (node, key)|
          genuine = @messages.find { |message| message.key == key }
          node.error!("imitates \"#{key}\", which isn't a genuine message in this shift") unless genuine&.legit?
          next if fake.arrives_at_start?
          next if [ fake.arrives_after_handled, fake.arrives_after ] == [ genuine.arrives_after_handled, genuine.arrives_after ]

          node.error!("imitates \"#{key}\" but could arrive after it: a fake must arrive at the start, or on exactly the " \
                      "same arrives: trigger as the message it imitates")
        end
      end

      # If a genuine message has a follow-up, so must a phish (the attacker chasing: "Did you get my
      # invoice?"). Otherwise "something arrived after I dealt with that" would mean it was genuine.
      def check_phishes_have_follow_ups_too
        genuine, phish = @messages.select(&:arrives_after).partition(&:legit?).map(&:size)
        return if phish >= genuine

        @node.error!("#{genuine} #{"genuine message".pluralize(genuine)} #{genuine == 1 ? "has a" : "have"} follow-up (arrives: { after: … }) but " \
                     "#{phish.zero? ? "no phish does" : "only #{phish} phish #{phish == 1 ? "does" : "do"}"}: phishes need at least as many, " \
                     "or a follow-up would hint that a message was genuine")
      end

      # Lazy play must never pay: reporting everything, archiving everything, clocking off at once, and
      # flagging every sentence then reporting everything must each stay below one star.
      def check_lazy_play_doesnt_pay
        exploits = Shift::LazyPlay.new(@shift.reload).exploits
        return if exploits.empty?

        @node.error!("lazy play scores too well: " + exploits.map { |strategy, card|
          "#{strategy.to_s.humanize(capitalize: false)} scores #{card.total} of #{card.total_max} (#{card.stars} #{"star".pluralize(card.stars)})"
        }.join("; ") + ". Add genuine messages that need doing, or make phishes worth less of the total")
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
