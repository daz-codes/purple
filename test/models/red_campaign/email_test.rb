require "test_helper"

class RedCampaign::EmailTest < ActiveSupport::TestCase
  test "the email is built only from the cards' text, escaped" do
    email = RedCampaign::Email.new(target_options(:overdue, :spoof, :link, :sign_in, :friday))

    assert_equal "Tidemark Supply <tidemark@freemail.test>", email.from
    assert_equal "URGENT", email.subject
    assert_equal "Friday, 4:55pm", email.sent_at
    assert_equal "A fake portal sign-in page.", email.payload
    assert_equal "<p>Payment is overdue &lt;today&gt;.</p><p>Pay here: portal.tidemark-billing.example/4471</p>", email.body_html
    assert email.body_html.html_safe?
  end

  test "an unfinished set of cards gives an unfinished email" do
    email = RedCampaign::Email.new([ target_options(:spoof) ])

    assert_nil email.subject
    assert_equal "", email.body_html
  end
end
