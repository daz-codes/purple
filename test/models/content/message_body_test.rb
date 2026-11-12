require "test_helper"

class Content::MessageBodyTest < ActiveSupport::TestCase
  BODY = <<~HTML
    <p>Our bank details have <strong>changed</strong>.</p>
    <ul><li>Pay within 1 hour</li></ul>
    <p><a href="https://contoso-portal.example.net/login">https://portal.contoso.example/invoices/4471</a></p>
  HTML

  test "assigns neutral ids to every paragraph, list item and link" do
    result = Content::MessageBody.call(BODY)

    assert_equal %w[ p1 p2 p3 l1 ], result.element_ids
    html = Nokogiri::HTML5.fragment(result.html)
    assert_equal %w[ p1 p2 p3 ], html.css("p, li").map { |node| node["id"] }
  end

  test "replaces links with spans that carry no real href" do
    result = Content::MessageBody.call(BODY)
    span = Nokogiri::HTML5.fragment(result.html).at_css("span#l1")

    assert_not_includes result.html, "<a"
    assert_not_includes result.html, "href"
    assert_equal "fake-link", span["data-controller"]
    assert_equal "l1", span["data-link-key"]
    assert_equal "https://portal.contoso.example/invoices/4471", span["data-display-url"]
    assert_equal "https://contoso-portal.example.net/login", span["data-actual-url"]
    assert_equal "0", span["tabindex"]
    assert_equal [ Content::MessageBody::ExtractedLink.new(key: "l1", href: "https://contoso-portal.example.net/login",
                                                          text: "https://portal.contoso.example/invoices/4471") ],
      result.links
  end

  test "keeps basic formatting" do
    assert_includes Content::MessageBody.call(BODY).html, "<strong>changed</strong>"
  end

  test "rejects anything outside the allowlist" do
    {
      "<script>alert(1)</script>" => "<script> is not allowed",
      "<style>p{}</style>" => "<style> is not allowed",
      %(<img src="https://cdn.example.com/x.png">) => "<img> is not allowed",
      %(<iframe src="https://a.example"></iframe>) => "<iframe> is not allowed",
      %(<p onclick="steal()">hi</p>) => "attribute onclick",
      %(<p style="color:red">hi</p>) => "attribute style",
      %(<p class="flag">hi</p>) => "attribute class",
      "<!-- the answer is p2 --><p>hi</p>" => "comments are not allowed"
    }.each do |html, message|
      error = assert_raises(Content::MessageBody::Invalid, html) { Content::MessageBody.call(html) }
      assert_includes error.message, message
    end
  end

  test "rejects author-supplied ids and data attributes, which could give answers away" do
    assert_raises(Content::MessageBody::Invalid, match: /id="flag-urgency"/) { Content::MessageBody.call(%(<p id="flag-urgency">x</p>)) }
    assert_raises(Content::MessageBody::Invalid, match: /data-legit/) { Content::MessageBody.call(%(<p data-legit="false">x</p>)) }
    assert_raises(Content::MessageBody::Invalid, match: /target/) { Content::MessageBody.call(%(<a href="https://a.example" target="_blank">x</a>)) }
  end

  test "rejects links to real or non-http destinations" do
    [ "https://www.realbank.com/login", "javascript:alert(1)", "http://192.0.2.1/" ].each do |href|
      assert_raises(Content::MessageBody::Invalid, href) { Content::MessageBody.call(%(<p><a href="#{href}">click</a></p>)) }
    end
  end

  test "rejects links without text or with nested markup" do
    assert_raises(Content::MessageBody::Invalid, match: /no text/) { Content::MessageBody.call(%(<a href="https://a.example"> </a>)) }
    assert_raises(Content::MessageBody::Invalid, match: /plain text/) { Content::MessageBody.call(%(<a href="https://a.example"><b>x</b></a>)) }
  end

  test "rejects real names in the text" do
    assert_raises(Content::MessageBody::Invalid, match: /realbank\.com/) { Content::MessageBody.call("<p>Log in at realbank.com</p>") }
  end

  test "rejects an empty body" do
    assert_raises(Content::MessageBody::Invalid) { Content::MessageBody.call("  ") }
  end
end
