# Saves (or unsaves) words from a message as a note: a sentence by its neutral anchor, or a highlighted
# range (from, to) of a paragraph's text. The reader comes back still in "save to notes" mode.
class ShiftAttempts::Messages::NotesController < ApplicationController
  include ShiftPlay
  include ShiftAttemptMessageScoped

  def create
    @note_mode = true
    play { @attempt.save_note(@message, params[:anchor], from: params[:from].presence, to: params[:to].presence) }
  end
end
