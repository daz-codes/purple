# Internal authoring rules, run within ShiftImport's transaction and shared import context.
class Content::ShiftImport
  module StoryLinks
    private
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
  end
end
