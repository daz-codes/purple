# One thing the player can hand over, as a chip to pick: a detail from their persona card, the live MFA
# code, or a note they saved. Only id, label and value are ever shown. The detail it is (and so how
# sensitive it is) stays on the server.
ShiftAttempt::Chip = Data.define(:id, :label, :value, :detail) do
  # What a share stores, so re-importing content can't change what an old attempt gave away.
  def to_shared
    { "chip" => id, "label" => label, "value" => value, "detail" => detail&.key, "sensitivity" => detail&.sensitivity }
  end
end
