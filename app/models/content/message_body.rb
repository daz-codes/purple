module Content
  # Turns an authored message body into the safe HTML the game renders.
  #
  # 1. Rejects anything outside a small allowlist: no scripts, styles, images, comments, or
  #    attributes other than href on links. Authors may not set ids or data attributes, so no
  #    element can be given a revealing name like "flag-urgency".
  # 2. Gives every paragraph-like element (p1, p2…) and every link (l1, l2…) a neutral id, so
  #    flaggable elements don't stand out from the rest.
  # 3. Replaces each <a> with a <span> carrying its key and URLs. No real href ever reaches the
  #    browser; clicking is handled by the server.
  # 4. Checks every URL, email address and host name is fictional (see ReservedNames).
  # 5. Runs the result through Rails' safe-list sanitizer as a second line of defence.
  class MessageBody
    Result = Data.define(:html, :element_ids, :links)
    ExtractedLink = Data.define(:key, :href, :text)

    class Invalid < StandardError; end

    FORMATTING_TAGS = %w[ p br strong em b i u ul ol li blockquote h3 h4 hr small ].freeze
    ID_TAGS = %w[ p li blockquote h3 h4 ].freeze
    OUTPUT_TAGS = (FORMATTING_TAGS + %w[ span ]).freeze
    OUTPUT_ATTRIBUTES = %w[
      id class role tabindex data-controller data-action data-link-key data-display-url data-actual-url
    ].freeze

    def self.call(html)
      new(html).call
    end

    def initialize(html)
      @html = html.to_s
    end

    def call
      raise Invalid, "body is empty" if @html.strip.empty?

      fragment = Nokogiri::HTML5.fragment(@html)
      check_allowlist!(fragment)
      check_text_is_fictional!(fragment)

      element_ids = assign_paragraph_ids(fragment)
      links = rewrite_links(fragment)
      html = sanitize(fragment.to_html)

      Result.new(html:, element_ids: element_ids + links.map(&:key), links:)
    end

    private
      def check_allowlist!(fragment)
        fragment.traverse do |node|
          raise Invalid, "comments are not allowed (they can leak answers in the page source)" if node.comment?
          next unless node.element?

          unless FORMATTING_TAGS.include?(node.name) || node.name == "a"
            raise Invalid, "<#{node.name}> is not allowed. Use only: #{(FORMATTING_TAGS + %w[a]).join(", ")}"
          end

          node.attribute_nodes.each do |attribute|
            next if node.name == "a" && attribute.name == "href"

            raise Invalid, "attribute #{attribute.name}=\"#{attribute.value}\" on <#{node.name}> is not allowed " \
                           "(the importer assigns neutral ids itself; only href on <a> is permitted)"
          end
        end
      end

      def check_text_is_fictional!(fragment)
        unreserved = ReservedNames.unreserved_names_in(fragment.text)
        return if unreserved.empty?

        raise Invalid, "uses names outside the reserved fictional set: #{unreserved.join(", ")}. " \
                       "Use example.com/.net/.org, or the .example, .test or .invalid domains"
      end

      def assign_paragraph_ids(fragment)
        fragment.css(ID_TAGS.join(", ")).each_with_index.map do |node, index|
          node["id"] = "p#{index + 1}"
        end
      end

      def rewrite_links(fragment)
        fragment.css("a").each_with_index.map do |anchor, index|
          key = "l#{index + 1}"
          href = anchor["href"].to_s.strip
          text = anchor.text.strip

          raise Invalid, "link #{key} (\"#{text}\") has no href" if href.empty?
          raise Invalid, "link #{key} has no text" if text.empty?
          unless ReservedNames.reserved_url?(href)
            raise Invalid, "link #{key} points to #{href}, which isn't an http(s) URL on a reserved fictional domain"
          end
          if anchor.element_children.any?
            raise Invalid, "link #{key} must contain plain text only"
          end

          span = fragment.document.create_element("span", text,
            "id" => key, "class" => "fake-link", "role" => "link", "tabindex" => "0",
            "data-controller" => "fake-link", "data-link-key" => key,
            "data-display-url" => text, "data-actual-url" => href)
          anchor.replace(span)

          ExtractedLink.new(key:, href:, text:)
        end
      end

      def sanitize(html)
        Rails::HTML5::SafeListSanitizer.new.sanitize(html, tags: OUTPUT_TAGS, attributes: OUTPUT_ATTRIBUTES)
      end
  end
end
