# Words for Red's Workshop: the card slots, and what each bot did with Red's email.
module WorkshopHelper
  SLOTS = {
    "pretext" => [ "The story", "What the email is about, and its subject line." ],
    "sender" => [ "The sender", "Who it seems to come from." ],
    "lure" => [ "The lure", "What you want them to click or open." ],
    "payload" => [ "What's behind it", "What happens when they do." ],
    "timing" => [ "The timing", "When it lands." ]
  }.freeze

  OUTCOMES = {
    "fooled" => [ "Fooled", :good ],
    "near_miss" => [ "Clicked, then backed out", :warn ],
    "verified" => [ "Got suspicious and checked", :neutral ],
    "reported" => [ "Reported it", :bad ]
  }.freeze

  def workshop_slot_title(category)
    SLOTS.fetch(category.to_s).first
  end

  def workshop_slot_hint(category)
    SLOTS.fetch(category.to_s).last
  end

  # [label, tone] from Red's point of view: fooling a bot is good for Red.
  def workshop_outcome(result)
    OUTCOMES.fetch(result["outcome"])
  end

  def workshop_outcome_points(result)
    { "fooled" => RedCampaign::Launchable::FOOLED, "near_miss" => RedCampaign::Launchable::NEAR_MISS }.fetch(result["outcome"], 0)
  end

  # What gave Red's email away to a bot, in words.
  def workshop_giveaway(result, technique)
    return unless technique

    case result["outcome"]
    when "near_miss" then "Clicked through, then spotted it: #{technique.red_flag_label.downcase_first}."
    when "reported" then "Spotted it in the email and reported it: #{technique.red_flag_label.downcase_first}."
    else "Didn't like the look of it and checked with the real sender first: #{technique.red_flag_label.downcase_first}."
    end
  end
end
