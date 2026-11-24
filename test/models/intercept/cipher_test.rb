require "test_helper"

class Intercept::CipherTest < ActiveSupport::TestCase
  test "every step round-trips, alone and stacked" do
    text = "Meet at Pier 3 at 0340, café & co."
    [
      %w[ to_base64 ], %w[ to_hex ], %w[ to_base32 ], %w[ url_encode ], %w[ reverse ], [ { "rot" => 13 } ], [ { "rot" => 7 } ],
      [ { "vigenere" => "KETTLE" } ], [ { "xor" => "SCONES" }, "to_hex" ], [ { "xor_hex" => "a1b2c3" }, "to_base64" ],
      [ "reverse", { "rot" => 3 }, "to_base64", "to_base64" ]
    ].each do |recipe|
      cipher = Intercept::Cipher.new(recipe)
      assert_equal text, cipher.decode(cipher.encode(text)).force_encoding("UTF-8"), recipe.inspect
    end
  end

  test "encodings match the usual vectors" do
    assert_equal "SGVsbG8=", Intercept::Cipher.new(%w[ to_base64 ]).encode("Hello")
    assert_equal "48656c6c6f", Intercept::Cipher.new(%w[ to_hex ]).encode("Hello")
    assert_equal "JBSWY3DP", Intercept::Cipher.new(%w[ to_base32 ]).encode("Hello")
    assert_equal "MZXW6YQ=", Intercept::Cipher.new(%w[ to_base32 ]).encode("foob")
    assert_equal "Uryyb, Jbeyq", Intercept::Cipher.new([ { "rot" => 13 } ]).encode("Hello, World")
    assert_equal "LXFOPVEFRNHR", Intercept::Cipher.new([ { "vigenere" => "LEMON" } ]).encode("ATTACKATDAWN")
  end

  test "Vigenère keeps case and skips anything that isn't a letter without using up the key" do
    assert_equal "Lxf, Opv!", Intercept::Cipher.new([ { "vigenere" => "LEMON" } ]).encode("Att, Ack!")
  end

  test "undo steps name the Workbench operations in order, with ROT turned the other way" do
    cipher = Intercept::Cipher.new([ { "rot" => 3 }, { "vigenere" => "KEY" }, "to_base64" ])
    assert_equal [ [ "from_base64", nil ], [ "vigenere_decode", "KEY" ], [ "rot", 23 ] ], cipher.undo_steps
  end

  test "rejects recipes it can't follow" do
    [
      [], "to_base64", %w[ to_rot13 ], [ { "rot" => 0 } ], [ { "rot" => 26 } ], [ { "rot" => "13" } ], [ { "vigenere" => "KEY1" } ],
      [ { "xor" => "" } ], [ { "xor_hex" => "abc" } ], [ { "to_base64" => true } ], [ { "rot" => 1, "xor" => "a" } ]
    ].each do |recipe|
      assert_raises(Intercept::Cipher::InvalidRecipe, recipe.inspect) { Intercept::Cipher.new(recipe) }
    end
  end
end
