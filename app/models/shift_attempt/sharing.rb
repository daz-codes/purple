# Handing over private details: picking chips (see ShiftAttempt::Chip) in a message's "Send details"
# box, or in the fields of a page opened from a link. There's never a text box, so nothing typed can
# reach the server: it records which chips were shared, with which message, and how.
#
# Each share is a share_details action whose result stores a copy of what was shared:
#   { "via" => "reply" | "page", "page" => the tab's source (pages only), "shared" => [chip copies],
#     "response" => what came back (replies only) }
# Whether sharing was right waits for the debrief (ShiftAttempt::Scorecard).
#
# The MFA code is live: it appears on the player's authenticator once they open a page that asks for
# it, genuine or not (a lookalike page relays the sign-in to the real one, as attackers' kits do, so a
# code arriving says nothing about the page). From then on it's a chip like any other.
module ShiftAttempt::Sharing
  extend ActiveSupport::Concern

  # Every share action, in order. Shared with the scorecard so both read shares the same way.
  def self.shares(actions)
    actions.select(&:share_details?)
  end

  # Sending details to a message that offers replies (its "Send details" box). The same answer comes
  # back however right or wrong it was.
  def share_details(message, chip_ids)
    acting_on(message) do
      reject "You can't send details to that message." if message.replies.empty?

      record :share_details, message:, result: { "via" => "reply", "shared" => shared_chips!(chip_ids), "response" => message.share_response_text }
    end
  end

  # Everything the player can hand over right now.
  def chips
    persona_chips + (mfa_code_visible? ? [ mfa_chip ] : []) + note_chips
  end

  # The details already sent to a message, as the player saw them: labels and values, and the answer.
  def shared_with(message)
    actions.select { |action| action.share_details? && action.target_key == message.key && action.result["via"] == "reply" }
      .map { |action| action.result.slice("shared", "response") }
  end

  # The six-digit code on the player's authenticator, once a sign-in page has asked for one.
  def mfa_code
    format("%06d", OpenSSL::HMAC.digest("SHA256", self.class.mfa_secret, token).unpack1("N") % 1_000_000) if mfa_code_visible?
  end

  def mfa_code_visible?
    actions.any? do |action|
      next false unless action.click_link?

      message = shift.messages.find { |candidate| candidate.key == action.target_key }
      message && ShiftAttempt::Tab.new(message:, source: action.result).fields.any? { |field| field.key == "mfa_code" }
    end
  end

  class_methods do
    def mfa_secret
      @mfa_secret ||= Rails.application.key_generator.generate_key("shift_attempt/mfa_code", 32)
    end
  end

  private
    # The fields on an open page, then pressing its button: chips put into a portal's or a lookalike
    # page's fields are shared with that page's message, before the button press is recorded.
    def share_on_page(tab, chip_ids)
      chip_ids = Array(chip_ids).compact_blank
      return if chip_ids.empty?

      reject "There's nowhere to put details on this page." if tab.fields.empty?
      reject "This page only has #{tab.fields.size} #{"field".pluralize(tab.fields.size)}." if chip_ids.size > tab.fields.size
      record :share_details, message: tab.message, result: { "via" => "page", "page" => tab.source, "shared" => shared_chips!(chip_ids) }
    end

    def shared_chips!(chip_ids)
      ids = Array(chip_ids).map(&:to_s).compact_blank.uniq
      reject "Pick at least one detail to send." if ids.empty?

      available = chips.index_by(&:id)
      ids.map { |id| (available[id] or reject "That isn't one of your details.").to_shared }
    end

    def persona_chips
      return [] unless persona.present?

      values = { "name" => persona.name, "role" => persona.role }.merge(persona_details)
      Shift::Detail::CARD.filter_map do |detail|
        ShiftAttempt::Chip.new(id: detail.key, label: detail.label, value: values[detail.key], detail:) if values[detail.key]
      end
    end

    def mfa_chip
      ShiftAttempt::Chip.new(id: "mfa_code", label: "MFA code", value: mfa_code, detail: Shift::Detail.card("mfa_code"))
    end

    def note_chips
      messages = shift.messages.index_by(&:key)
      notes.map do |note|
        ShiftAttempt::Chip.new(id: note.id, label: "Note", value: note.text, detail: note.detail_in(messages[note.message_key]))
      end
    end
end
