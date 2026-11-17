# Internal authoring rules, run within MissionImport's transaction and shared import context.
class Content::MissionImport
  module PrivateDetails
    private
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
          detail_node.error!("key \"#{key}\" is a persona card detail; learned details need their own keys") if key.in?(Mission::Detail::CARD_KEYS)
          target = red_flag_target(detail_node, message)
          detail_node.error!("a detail is quoted from the message's text: give quote:, not anchor:") unless target[:quote]

          { "key" => key, "label" => fictional(detail_node, :label, detail_node.required(:label)),
            "sensitivity" => one_of(detail_node, :sensitivity, Mission::Detail::SENSITIVITIES - %w[ never ]),
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
      # - within the mission, every internal detail a phish wants is needed by a genuine message, and the
      #   other way round, so being asked for one never says who's asking.
      def check_private_details
        learned = @messages.flat_map { |message| message.learned_details.map { |detail| [ detail, message ] } }
        @node.check_unique!("learned detail", learned.map { |detail, _| detail.key })
        catalogue = (Mission::Detail::CARD + learned.map(&:first)).index_by(&:key)

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
  end
end
