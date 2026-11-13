# The text of one paragraph-like block of a message body (p1, p2…), as the player sees it, with the
# importer's sentence anchors (p1s1, p1s2…) and where each sentence starts and ends in that text.
#
# Highlights and quoted red flags are character ranges in this text. The text is normalised the same
# way on both sides: the block's text nodes in order, with every run of whitespace collapsed to one
# space and the ends trimmed. The browser applies the same rule to the element's textContent (see
# flag_mode_controller.js), so a selection's offsets mean the same characters to both.
class Message::Paragraph
  Sentence = Data.define(:anchor, :from, :to)

  BLOCK_ANCHOR = /\Ap\d+\z/
  SENTENCE_ANCHOR = /\Ap\d+s\d+\z/

  attr_reader :anchor, :text, :sentences

  def initialize(anchor:, text:, sentences:)
    @anchor = anchor
    @text = text
    @sentences = sentences
  end

  # Every leaf block (one with no anchored blocks inside it) in stored body HTML.
  def self.all_in(body_html)
    Nokogiri::HTML5.fragment(body_html).css("[data-anchor]").filter_map do |node|
      next unless node["data-anchor"].match?(BLOCK_ANCHOR)
      next if node.css("[data-anchor]").any? { |inner| inner["data-anchor"].match?(BLOCK_ANCHOR) }

      raw = node.text
      sentences = raw_sentences_in(node).map do |anchor, from, to|
        Sentence.new(anchor:, from: normalized_offset(raw, from), to: normalized_offset(raw, to))
      end
      new(anchor: node["data-anchor"], text: normalize(raw), sentences:)
    end
  end

  def self.normalize(text)
    text.gsub(/\s+/, " ").strip
  end

  # Where raw position p of the text falls in its normalised form.
  def self.normalized_offset(raw, position)
    [ raw[0...position].gsub(/\s+/, " ").sub(/\A /, "").length, normalize(raw).length ].min
  end

  def self.raw_sentences_in(node, sentences = [], offset = [ 0 ])
    node.children.each do |child|
      if child.text?
        offset[0] += child.text.length
      elsif child.element? && child["data-anchor"].to_s.match?(SENTENCE_ANCHOR)
        sentences << [ child["data-anchor"], offset[0], offset[0] + child.text.length ]
        offset[0] += child.text.length
      elsif child.element?
        raw_sentences_in(child, sentences, offset)
      end
    end
    sentences
  end
  private_class_method :raw_sentences_in

  def sentence(anchor)
    sentences.find { |sentence| sentence.anchor == anchor }
  end

  # The sentence that the range from...to lies inside, if any.
  def sentence_containing(from, to)
    sentences.find { |sentence| sentence.from <= from && to <= sentence.to }
  end

  # Whether the range is exactly one whole sentence: a sentence click, or the same words dragged over.
  def whole_sentence?(from, to)
    sentences.any? { |sentence| trim(sentence.from, sentence.to) == [ from, to ] }
  end

  # The range narrowed to leave out whitespace at either end, or nil if it's out of bounds or nothing
  # but whitespace.
  def trim(from, to)
    return unless from.is_a?(Integer) && to.is_a?(Integer) && 0 <= from && from < to && to <= text.length

    from += 1 while from < to && text[from].match?(/\s/)
    to -= 1 while to > from && text[to - 1].match?(/\s/)
    [ from, to ] if to > from
  end

  def excerpt(from, to)
    text[from...to].squish
  end
end
