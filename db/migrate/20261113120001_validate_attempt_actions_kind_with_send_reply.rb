class ValidateAttemptActionsKindWithSendReply < ActiveRecord::Migration[8.2]
  def change
    validate_check_constraint :attempt_actions, name: "attempt_actions_kind"
  end
end
