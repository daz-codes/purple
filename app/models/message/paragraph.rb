# The text of one paragraph-like block of a message body (p1, p2…), as the player sees it, with the
# importer's sentence anchors (p1s1, p1s2…) and where each sentence starts and ends in that text.
#
# Highlights and quoted red flags are character ranges in this text. The browser measures a selection
# against the same text (the block's textContent), so the two agree.
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

      new(anchor: node["data-anchor"], text: node.text, sentences: sentences_in(node))
    end
  end

  def self.sentences_in(node, sentences = [], offset = [ 0 ])
    node.children.each do |child|
      if child.text?
        offset[0] += child.text.length
      elsif child.element? && child["data-anchor"].to_s.match?(SENTENCE_ANCHOR)
        sentences << Sentence.new(anchor: child["data-anchor"], from: offset[0], to: offset[0] + child.text.length)
        offset[0] += child.text.length
      elsif child.element?
        sentences_in(child, sentences, offset)
      end
    end
    sentences
  end
  private_class_method :sentences_in

  def sentence(anchor)
    sentences.find { |sentence| sentence.anchor == anchor }
  end

  # Whether the range from...to lies inside a single sentence.
  def within_one_sentence?(from, to)
    sentences.any? { |sentence| sentence.from <= from && to <= sentence.to }
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
