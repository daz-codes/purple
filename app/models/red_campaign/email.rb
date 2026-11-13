# The email a campaign's cards add up to, exactly as Blue would see it. Every word comes from the
# cards' pre-written text, escaped: there's no free text anywhere.
#
#   sender:  "Display Name <address>"
#   pretext: the subject, and the opening paragraph
#   lure:    the paragraph with the link or attachment
#   timing:  when it lands
# The payload is what's behind the lure, so it isn't in the email itself.
class RedCampaign::Email
  include ERB::Util

  def initialize(options)
    @options = options.index_by(&:category)
  end

  def from
    @options["sender"]&.rendered_value
  end

  def subject
    @options["pretext"]&.subject
  end

  def sent_at
    @options["timing"]&.rendered_value
  end

  def payload
    @options["payload"]&.rendered_value
  end

  def body_html
    %w[ pretext lure ].filter_map { |category| @options[category] }
      .map { |option| "<p>#{html_escape(option.rendered_value)}</p>" }.join.html_safe
  end
end
