# The encodings and ciphers a signals mission uses, in Ruby: the twin of the Workbench's operations
# (app/javascript/workbench/operations.js). Content is authored as plaintext plus the recipe that
# encodes it, and the importer builds the ciphertext with #encode, so every intercept is known to
# decode, step by step in the Workbench, back to its solution.
#
# A recipe is a list of steps, each a name or a one-key mapping of name to argument:
#   [ { vigenere: CRUMPET }, to_base64 ]
# Everything works on binary strings (bytes); text is UTF-8.
class Intercept::Cipher
  # Each encoding step, and the Workbench operation (with its argument) that undoes it.
  STEPS = {
    "to_base64" => { undo: "from_base64" },
    "to_hex" => { undo: "from_hex" },
    "to_base32" => { undo: "from_base32" },
    "url_encode" => { undo: "url_decode" },
    "reverse" => { undo: "reverse" },
    "rot" => { argument: :shift, undo: "rot" },
    "vigenere" => { argument: :key, undo: "vigenere_decode" },
    "xor" => { argument: :text, undo: "xor" },
    "xor_hex" => { argument: :hex, undo: "xor_hex" }
  }.freeze

  BASE32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze

  class InvalidRecipe < StandardError; end

  Step = Data.define(:name, :argument)

  def self.parse(recipe)
    raise InvalidRecipe, "must be a list of steps" unless recipe.is_a?(Array) && recipe.any?

    recipe.map do |step|
      name, argument = step.is_a?(Hash) && step.size == 1 ? step.first : [ step, nil ]
      name = name.to_s
      spec = STEPS[name] or raise InvalidRecipe, "unknown step #{name.inspect} (allowed: #{STEPS.keys.join(", ")})"
      check_argument(name, spec[:argument], argument)
      Step.new(name:, argument:)
    end
  end

  def self.check_argument(name, kind, argument)
    case kind
    when nil then raise InvalidRecipe, "#{name} takes no argument" unless argument.nil?
    when :shift then raise InvalidRecipe, "rot needs a shift from 1 to 25" unless argument.is_a?(Integer) && argument.between?(1, 25)
    when :key then raise InvalidRecipe, "vigenere needs a key of letters" unless argument.is_a?(String) && argument.match?(/\A[A-Za-z]+\z/)
    when :text then raise InvalidRecipe, "xor needs a key" unless argument.is_a?(String) && argument.present?
    when :hex then raise InvalidRecipe, "xor_hex needs a key of hex digits" unless argument.is_a?(String) && argument.match?(/\A(\h\h)+\z/)
    end
  end
  private_class_method :check_argument

  def initialize(recipe)
    @steps = self.class.parse(recipe)
  end

  # The ciphertext the player is given.
  def encode(plaintext)
    @steps.reduce(plaintext.b) { |bytes, step| apply(step.name, step.argument, bytes) }
  end

  # The Workbench steps that undo the recipe, in order: [[operation, argument], ...]. Shown in the
  # debrief, never before.
  def undo_steps
    @steps.reverse.map do |step|
      argument = step.name == "rot" ? 26 - step.argument : step.argument
      [ STEPS.fetch(step.name)[:undo], argument ]
    end
  end

  def decode(ciphertext)
    undo_steps.reduce(ciphertext.b) { |bytes, (name, argument)| apply(name, argument, bytes) }
  end

  private
    def apply(name, argument, bytes)
      case name
      when "to_base64" then [ bytes ].pack("m0")
      when "from_base64" then bytes.unpack1("m")
      when "to_hex" then bytes.unpack1("H*")
      when "from_hex" then [ bytes.delete("^0-9a-fA-F") ].pack("H*")
      when "to_base32" then to_base32(bytes)
      when "from_base32" then from_base32(bytes)
      when "url_encode" then ERB::Util.url_encode(bytes.dup.force_encoding("UTF-8")).b
      when "url_decode" then CGI.unescape(bytes).b
      when "reverse" then bytes.reverse
      when "rot" then rot(bytes, argument)
      when "vigenere" then vigenere(bytes, argument, 1)
      when "vigenere_decode" then vigenere(bytes, argument, -1)
      when "xor" then xor(bytes, argument.b)
      when "xor_hex" then xor(bytes, [ argument ].pack("H*"))
      end.b
    end

    def rot(bytes, shift)
      bytes.bytes.map { |byte| shift_letter(byte, shift) }.pack("C*")
    end

    # Letters shift by the key's letters in turn; anything else passes through without using up a key letter.
    def vigenere(bytes, key, direction)
      shifts = key.upcase.bytes.map { |letter| letter - 65 }
      index = 0
      bytes.bytes.map { |byte|
        next byte unless letter?(byte)

        shifted = shift_letter(byte, direction * shifts[index % shifts.size])
        index += 1
        shifted
      }.pack("C*")
    end

    def shift_letter(byte, shift)
      base = if byte.between?(65, 90) then 65 elsif byte.between?(97, 122) then 97 end
      base ? base + (byte - base + shift) % 26 : byte
    end

    def letter?(byte)
      byte.between?(65, 90) || byte.between?(97, 122)
    end

    def xor(bytes, key)
      bytes.bytes.each_with_index.map { |byte, index| byte ^ key.getbyte(index % key.bytesize) }.pack("C*")
    end

    def to_base32(bytes)
      bits = bytes.unpack1("B*")
      encoded = bits.scan(/.{1,5}/).map { |chunk| BASE32[chunk.ljust(5, "0").to_i(2)] }.join
      encoded.ljust((encoded.size / 8.0).ceil * 8, "=")
    end

    def from_base32(text)
      bits = text.upcase.delete("^A-Z2-7").chars.map { |char| BASE32.index(char).to_s(2).rjust(5, "0") }.join
      [ bits[0, bits.size - bits.size % 8] ].pack("B*")
    end
end
