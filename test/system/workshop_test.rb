require "application_system_test_case"

# Builds and launches a campaign at the fixture target (budget 9) and its two bots.
class WorkshopTest < ApplicationSystemTestCase
  test "read the recon, build an email from cards, launch it and read the debrief" do
    sign_in users(:one)
    click_on "Workshop"
    click_on "Month-end at Larkhill"
    assert_text "Tidemark's invoice is due this week."
    click_on "Start a campaign"

    # The builder never shows how well a card fits the target, or how hard it is to spot.
    html = page.html
    assert_not_includes html, "relevance"
    assert_not_includes html, "stealth"

    within("[data-testid=slot-pretext]") { click_on "Bank change" }
    assert_selector "[data-testid=budget]", text: "6 of 9 left"
    within("[data-testid=email-preview]") do
      assert_text "New bank details"
      assert_text "Our bank details have changed."
    end

    # Swap a card, and find one that doesn't fit the budget.
    within("[data-testid=slot-sender]") { click_on "Lookalike" }
    assert_selector "[data-testid=budget]", text: "3 of 9 left"
    within("[data-testid=slot-sender]") { click_on "Spoof" }
    assert_selector "[data-testid=budget]", text: "5 of 9 left"

    within("[data-testid=slot-lure]") { click_on "Link" }
    within("[data-testid=slot-payload]") { click_on "Sign in" }
    assert_selector "[data-testid=still-to-pick]", text: "the timing"
    within("[data-testid=slot-timing]") { click_on "Friday" }
    assert_selector "[data-testid=budget]", text: "1 of 9 left"

    within("[data-testid=email-preview]") do
      assert_text "Tidemark Supply <tidemark@freemail.test>"
      assert_text "Friday, 4:55pm"
      assert_text "Pay here: portal.tidemark-billing.example/4471"
    end

    accept_confirm { click_on "Launch at the Blue bots" }

    assert_selector "h2", text: "What the bots did"
    assert_selector "[data-testid=bot-result]", count: 2
    campaign = RedCampaign.sole
    assert_selector "[data-testid=campaign-score]", text: campaign.score.to_s
    assert_text "Busy Bob"
    assert_text "Careful Carol"
    assert_text "Your playbook, and how Blue beats it"
    assert_text "Confirm bank changes by phone."
  end
end
