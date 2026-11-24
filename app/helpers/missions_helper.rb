module MissionsHelper
  KIND_LABELS = { "inbox" => "Inbox", "messages" => "Messages", "signals" => "Signals" }.freeze

  def mission_kind_label(mission)
    KIND_LABELS.fetch(mission.kind)
  end
end
