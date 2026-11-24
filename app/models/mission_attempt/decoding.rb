# A signals mission: a queue of intercepts, each answered by submitting its flag. The browser knows an
# intercept only by #intercept_ref, an opaque HMAC like a message's, so an authored key such as
# "meeting_time" never reaches the page.
#
# A submission is the one free-text field in play (docs/PLAN-phase-2.md, section 3, rule 3): it's capped
# at ANSWER_LIMIT characters with control characters stripped, filtered from the logs, saved on the
# attempt for the debrief and always rendered escaped. The player is told straight away whether a flag
# is right, as in any capture-the-flag puzzle: the flag is something they decoded, so knowing it's right
# gives nothing else away. Each intercept takes MAX_WRONG wrong answers before it closes, and every
# wrong answer costs points (see InterceptScorecard), so guessing doesn't pay.
#
# The mission is cleared once every intercept is solved or closed.
module MissionAttempt::Decoding
  extend ActiveSupport::Concern

  ANSWER_LIMIT = 200
  MAX_WRONG = 5

  def intercepts
    mission.intercepts
  end

  def intercept_ref(intercept)
    OpenSSL::HMAC.hexdigest("SHA256", self.class.message_ref_secret, "intercept:#{token}:#{intercept.key}").first(16)
  end

  def find_intercept(ref)
    ref = ref.to_s
    intercepts.find { |intercept| ActiveSupport::SecurityUtils.secure_compare(intercept_ref(intercept), ref) }
  end

  def submit_flag(intercept, answer)
    answer = self.class.clean_answer(answer)
    acting_on do
      reject "Type what you found before submitting." if answer.empty?
      reject "You've already found that flag." if solved?(intercept)
      reject "That intercept is closed: you've used all #{MAX_WRONG} tries." if closed?(intercept)

      correct = intercept.flag?(answer)
      record :submit_flag, target_key: intercept.key, result: { "answer" => answer, "correct" => correct }
      correct
    end
  end

  def submissions(intercept)
    actions.select { |action| action.submit_flag? && action.target_key == intercept.key }
  end

  def solved?(intercept)
    submissions(intercept).any? { |action| action.result["correct"] }
  end

  def wrong_answers(intercept)
    submissions(intercept).count { |action| !action.result["correct"] }
  end

  def tries_left(intercept)
    MAX_WRONG - wrong_answers(intercept)
  end

  # Solved, or out of tries.
  def closed?(intercept)
    solved?(intercept) || tries_left(intercept) <= 0
  end

  def intercepts_cleared?
    intercepts.any? && intercepts.all? { |intercept| closed?(intercept) }
  end

  class_methods do
    def clean_answer(answer)
      answer.to_s.gsub(/[[:cntrl:]]/, " ").strip.first(ANSWER_LIMIT)
    end
  end
end
