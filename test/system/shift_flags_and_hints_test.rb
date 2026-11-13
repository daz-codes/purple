require "application_system_test_case"

# Flag mode and hints on the fixture month-end shift. The fake invoice's red flags: its sender, and
# the words "Please pay today" in "Please pay today. Our bank details have changed."
class ShiftFlagsAndHintsTest < ApplicationSystemTestCase
  test "flag a part, highlight words and a sentence, take a hint, and see it all in the debrief" do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"
    within("#shift_inbox") { click_on "This week at Larkhill" }
    within("#shift_reader") do
      assert_selector "h2", text: "This week at Larkhill"
      click_on "Archive"
    end
    within("#shift_inbox") { click_on "URGENT invoice" }

    within("#shift_reader") do
      assert_selector "h2", text: "URGENT invoice"
      click_on "🚩 Flag red flags"
      assert_text "Flag mode."

      find("[data-anchor=from]").click
      assert_selector "[data-testid=your-flags]", text: "the sender"
      assert_selector "[data-anchor=from].flagged"

      # Drag over just the words "Please pay today".
      highlight "p1", "Please pay today"
      assert_selector "[data-testid=your-flags]", text: "the sender and “Please pay today”"

      # Click a sentence to flag the whole of it, and click it again to take it off.
      find("[data-anchor=p1s2]").click
      assert_selector "[data-testid=your-flags]", text: "“Our bank details have changed.”"
      find("[data-anchor=p1s2]").click
      assert_no_text "“Our bank details have changed.”"

      # In flag mode a link is flagged, not visited.
      find(".fake-link", text: "Pay now").click
      assert_selector "[data-testid=your-flags]", text: "the link “Pay now”"
    end
    assert_no_selector "dialog[open]"
    assert_no_answers

    within("#shift_hints") do
      accept_confirm { click_on "Take a hint" }
      assert_selector "[data-testid=hints]", text: "Compare the sender domains."
    end

    within("#shift_reader") { click_on "Report phishing" }
    accept_confirm { click_on "Give up" }

    assert_selector "[data-testid=debrief-hints]", text: "Hints: −21"
    phish = all("[data-testid=debrief-message]").find { |card| card.has_text?("URGENT invoice") }
    within(phish) do
      assert_selector "[data-testid=debrief-red-flags]", text: "Flagged +10 Lookalike sender domain."
      assert_selector "[data-testid=debrief-red-flags]", text: "Flagged +10 Rushed payment. “Please pay today”"
      assert_text "You also flagged the link “Pay now”, which wasn't a giveaway (−10)."
      assert_selector "[data-testid=debrief-marked-text] mark", text: "Please pay today"
    end
  end

  private
    # Selects the words in a paragraph of the reader, as a drag would, then releases the mouse there.
    def highlight(anchor, words)
      execute_script(<<~JS, anchor, words)
        const [anchor, words] = arguments
        const block = document.querySelector(`#shift_reader [data-anchor="${anchor}"]`)
        const walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT)
        for (let node = walker.nextNode(); node; node = walker.nextNode()) {
          const at = node.textContent.indexOf(words)
          if (at < 0) continue
          const range = document.createRange()
          range.setStart(node, at)
          range.setEnd(node, at + words.length)
          const selection = window.getSelection()
          selection.removeAllRanges()
          selection.addRange(range)
          node.parentElement.dispatchEvent(new MouseEvent("click", { bubbles: true, cancelable: true }))
          return
        }
      JS
    end
end
