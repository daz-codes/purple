require "application_system_test_case"

# The Purple debrief on the fixture shift: the legitimate invoice holds the link for the only task;
# the phish (a lookalike sign-in link and a .pdf.exe) arrives at minute 3.
class ShiftDebriefTest < ApplicationSystemTestCase
  test "the debrief explains each message: what it was, what you did and what to do next time" do
    sign_in users(:one)
    visit shift_path(shifts(:month_end))
    click_on "Start shift"

    click_on "Wait for new mail (3 min)"
    within("#shift_inbox") { click_on "URGENT invoice" }
    within("#shift_reader") { click_on "Open attachment Remittance_4471.pdf.exe" }
    within("dialog") { click_on "Open file" }
    assert_selector "[role=alert]", text: "Your files are being encrypted"
    within("#shift_reader") { click_on "Report phishing (1 min)" }
    within("#shift_inbox") { assert_text "Reported (1)" }

    accept_confirm { click_on "End shift" }

    assert_selector "h2", text: "Message by message"
    # -20 for the missed task; 30 for the report less 50 for running the file.
    assert_selector "[data-testid=score]", text: "0"
    assert_text "out of 70"
    assert_selector "[data-testid=stars]", text: "☆☆☆"
    assert_selector "[data-testid=debrief-headline]", text: "You reported 1 of 1 phish, fell for 1, and finished 0 of 1 task on time."

    phish, genuine = all("[data-testid=debrief-message]").partition { |card| card.has_text?("URGENT invoice") }.map(&:first)
    within(phish) do
      assert_selector "[data-testid=debrief-verdict]", text: "Phish: you fell for it"
      assert_selector "[data-testid=debrief-points]", text: "−20"
      assert_text "You opened Remittance_4471.pdf.exe. It wasn't a document"
      assert_text "You reported it afterwards"
      assert_text "one that ends in .exe is a program"
      assert_text "Lookalike sender domain"
      assert_text "Lookalike domain"
    end
    within(genuine) do
      assert_selector "[data-testid=debrief-verdict]", text: "Genuine"
      assert_text "it was the way to “Approve invoice”, which you didn't finish"
    end

    find("summary", text: "Your shift, minute by minute").click
    within("[data-testid=debrief-timeline]") { assert_text "Ran Remittance_4471.pdf.exe: compromised" }
  end
end
