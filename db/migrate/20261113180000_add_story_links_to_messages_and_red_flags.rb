# M6b, "Read it, you'll need it later": a red flag can contradict a fact in an earlier message, and a
# message that asks a question can say which earlier message held the answer. Both name the other
# message by key, like arrives_after, and quote the words that matter.
class AddStoryLinksToMessagesAndRedFlags < ActiveRecord::Migration[8.2]
  def change
    add_column :red_flags, :contradicts_key, :string
    add_column :red_flags, :contradicts_quote, :text
    add_column :messages, :answer_in_key, :string
    add_column :messages, :answer_in_quote, :text

    # Content tables, rewritten by every import and small: no long locks to worry about.
    safety_assured do
      add_check_constraint :red_flags, "(contradicts_key IS NULL) = (contradicts_quote IS NULL)", name: "red_flags_contradicts_complete"
      add_check_constraint :messages, "(answer_in_key IS NULL) = (answer_in_quote IS NULL)", name: "messages_answer_in_complete"
      add_check_constraint :messages, "answer_in_key IS NULL OR (legit AND expects = 'reply')", name: "messages_answer_in_only_when_asking"
    end
  end
end
