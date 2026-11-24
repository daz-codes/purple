# The Workbench's operations: a CyberChef-style chain the player builds to decode an intercept. They run
# in the browser (app/javascript/workbench/operations.js) on what the player already has, which is safe
# because the flag is only ever checked on the server. This list names them for the page and the debrief;
# the undo steps of Intercept::Cipher are a subset of them.
class Intercept::Workbench
  # argument: what the step asks for, if anything. shift: 1 to 25; key: letters; text: any text;
  # hex: hex digits; pattern: a regular expression.
  Operation = Data.define(:name, :label, :group, :argument)

  OPERATIONS = [
    Operation.new("from_base64", "From Base64", "Encodings", nil),
    Operation.new("to_base64", "To Base64", "Encodings", nil),
    Operation.new("from_hex", "From hex", "Encodings", nil),
    Operation.new("to_hex", "To hex", "Encodings", nil),
    Operation.new("from_base32", "From Base32", "Encodings", nil),
    Operation.new("url_decode", "URL decode", "Encodings", nil),
    Operation.new("reverse", "Reverse", "Encodings", nil),
    Operation.new("rot", "ROT (shift letters)", "Ciphers", "shift"),
    Operation.new("rot_all", "Try every ROT shift", "Ciphers", nil),
    Operation.new("vigenere_decode", "Vigenère decode", "Ciphers", "key"),
    Operation.new("xor", "XOR with a text key", "Ciphers", "text"),
    Operation.new("xor_hex", "XOR with a hex key", "Ciphers", "hex"),
    Operation.new("frequency", "Letter frequencies", "Analysis", nil),
    Operation.new("find_all", "Find all and join (pattern)", "Analysis", "pattern"),
    Operation.new("strings", "Strings (readable runs)", "Analysis", nil),
    Operation.new("metadata", "File metadata", "Forensics", nil),
    Operation.new("lsb", "Hidden bits (lowest bit of each colour)", "Forensics", nil)
  ].freeze

  ARGUMENT_LABELS = { "shift" => "Shift", "key" => "Key", "text" => "Key", "hex" => "Hex key", "pattern" => "Pattern" }.freeze

  def self.operation(name)
    OPERATIONS.find { |operation| operation.name == name.to_s } or raise ArgumentError, "no Workbench operation #{name}"
  end

  def self.grouped
    OPERATIONS.group_by(&:group)
  end

  # "ROT (shift letters): 13", for the debrief's list of steps.
  def self.describe(name, argument)
    label = operation(name).label
    argument.nil? ? label : "#{label}: #{argument}"
  end
end
