require "test_helper"

class MissionAttempt::IdentifiedTest < ActiveSupport::TestCase
  setup do
    @attempt = MissionAttempt.start(user: users(:one), mission: missions(:month_end))
  end

  test "an attempt gets its own persona details when it starts, from the mission's profile" do
    persona = @attempt.persona

    assert persona.present?
    assert_equal [ "Robin Ashby", "Accounts payable clerk", "Name of the office dog?" ], [ persona.name, persona.role, persona.security_question ]
    assert_match(/\ALH-\d{5}\z/, persona.staff_number)
    assert_match(/\A[23]\d{3}\z/, persona.extension)
    assert_match(/\A[A-Z]+ [A-Z]+\z/, persona.memorable_word)
    assert_includes MissionAttempt::Persona::NAMES, persona.security_answer
  end

  test "the details are stored, so they stay the same for the whole attempt" do
    details = @attempt.persona_details

    assert_equal details, MissionAttempt.find(@attempt.id).persona_details
    assert_equal details, MissionAttempt.start(user: users(:one), mission: missions(:month_end)).persona_details
  end

  test "the card shows the stored details, so changing the word lists can't rewrite them" do
    @attempt.update_column(:persona_details, @attempt.persona_details.merge("memorable_word" => "OLD WORDS"))

    assert_equal "OLD WORDS", MissionAttempt.find(@attempt.id).persona.memorable_word
  end

  test "different attempts get different details" do
    @attempt.stand_down
    others = 5.times.map do
      MissionAttempt.start(user: users(:one), mission: missions(:month_end)).tap(&:stand_down).persona_details
    end

    assert_operator (others + [ @attempt.persona_details ]).uniq.size, :>, 1
  end

  test "generating from the same seed gives the same details" do
    mission = missions(:month_end)

    assert_equal MissionAttempt::Persona.generate(mission:, seed: 42), MissionAttempt::Persona.generate(mission:, seed: 42)
  end

  test "a mission without a persona has none to show" do
    attempt = MissionAttempt.start(user: users(:one), mission: missions(:site_visit))

    assert_not attempt.persona.present?
  end

  test "the word lists are fiction only" do
    words = MissionAttempt::Persona::ADJECTIVES + MissionAttempt::Persona::NOUNS + MissionAttempt::Persona::NAMES

    assert_empty Content::ReservedNames.unreserved_names_in(words.join(" "))
    assert_equal words.size, words.uniq.size
  end
end
