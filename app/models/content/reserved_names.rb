module Content
  # Content must be fiction only. These are the names reserved for documentation and testing,
  # so they can never point at a real organisation:
  #
  # - Domains (RFC 2606 / RFC 6761): example.com, example.net, example.org and their
  #   subdomains, plus anything under the .example, .test and .invalid top-level domains.
  # - UK phone numbers Ofcom reserves for drama: 07700 900000 to 07700 900999.
  # - Alphanumeric SMS sender IDs (up to 11 characters, no digits-only IDs), which aren't routable,
  #   as long as they don't name a real brand.
  #
  # Real brands: there's no reserved list for company names, so REAL_BRANDS blocks the names most
  # often impersonated in phishing. It can't be exhaustive, so content review still matters; add
  # to it whenever a real name slips through. Only distinctive names are listed, because the check
  # runs on all player-visible text (so no "Apple", "Chase" or "Visa", which are ordinary words;
  # names that are only sometimes words, like "UPS" or "Zoom", must match their exact case).
  module ReservedNames
    RESERVED_SECOND_LEVEL = %w[ example.com example.net example.org ].freeze
    RESERVED_TOP_LEVEL = %w[ example test invalid ].freeze

    URL_PATTERN = %r{\b(?:https?|ftp)://[^\s<>"']+}i
    EMAIL_PATTERN = /\b[A-Z0-9._%+-]+@([A-Z0-9-]+(?:\.[A-Z0-9-]+)+)\b/i
    # Anything shaped like a host name in running text: "www.real-bank.com", "realbank.co.za",
    # "evil.tv". There are over 1,400 top-level domains and new ones keep arriving, so every
    # dotted name with an alphabetic ending counts unless it's reserved or a file name.
    BARE_HOST_PATTERN = /\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[a-z]{2,24})\b/i
    # File extensions that aren't also top-level domains, so "Invoice_4471.pdf" isn't a host.
    # Extensions that *are* TLDs (.zip, .mov) are deliberately missing: "evil.zip" is a real domain.
    FILE_EXTENSIONS = %w[
      pdf exe doc docx xls xlsx xlsm ppt pptx txt csv rtf odt ods png jpg jpeg gif svg html htm js iso
      img msi bat cmd ps1 vbs scr lnk rar 7z gz tar eml ics vcf
    ].freeze

    # Distinctive names, matched in any case ("paypal", "PAYPAL").
    REAL_BRANDS = [
      "PayPal", "HMRC", "DVLA", "Royal Mail", "Evri", "Hermes", "DHL", "FedEx", "Parcelforce", "USPS", "Amazon",
      "eBay", "Netflix", "Spotify", "Microsoft", "Office 365", "OneDrive", "SharePoint", "Google", "Gmail",
      "YouTube", "iCloud", "iPhone", "Apple ID", "Facebook", "Instagram", "WhatsApp", "LinkedIn", "Twitter",
      "TikTok", "Dropbox", "DocuSign", "Adobe", "Coinbase", "Binance", "Barclays", "HSBC", "Lloyds", "NatWest",
      "Santander", "Monzo", "Revolut", "Mastercard", "American Express", "Wells Fargo", "Citibank",
      "Bank of America", "Vodafone", "Virgin Media", "Tesco", "Sainsbury's", "Walmart", "GOV.UK", "Roblox",
      "Fortnite"
    ].freeze
    # Names that are also ordinary words, matched only exactly as written ("UPS", not "ups and downs").
    REAL_BRANDS_EXACT_CASE = %w[ UPS DPD BT O2 EE IRS NHS Amex Zoom Slack Outlook Steam Nationwide Halifax ].freeze
    BRAND_PATTERN = Regexp.union(
      /(?<![[:alnum:]])(?:#{REAL_BRANDS.map { |brand| Regexp.escape(brand) }.join("|")})(?![[:alnum:]])/i,
      /(?<![[:alnum:]])(?:#{REAL_BRANDS_EXACT_CASE.map { |brand| Regexp.escape(brand) }.join("|")})(?![[:alnum:]])/
    )

    module_function

    def reserved_host?(host)
      host = host.to_s.downcase.delete_suffix(".")
      return false if host.empty?

      RESERVED_SECOND_LEVEL.any? { |domain| host == domain || host.end_with?(".#{domain}") } ||
        RESERVED_TOP_LEVEL.include?(host.split(".").last)
    end

    def reserved_url?(url)
      uri = URI.parse(url.to_s.strip)
      uri.is_a?(URI::HTTP) && reserved_host?(uri.host)
    rescue URI::InvalidURIError
      false
    end

    def reserved_email?(address)
      local, domain = address.to_s.strip.split("@", 2)
      local.present? && reserved_host?(domain)
    end

    # A message sender or recipient: an email address, a reserved phone number or an SMS sender ID.
    def reserved_address?(address)
      address = address.to_s.strip
      return reserved_email?(address) if address.include?("@")
      return reserved_phone?(address) if address.match?(/\A\+?[\d\s()-]+\z/)

      address.match?(/\A(?=.*[A-Za-z])[A-Za-z0-9 ]{1,11}\z/) && real_brands_in(address).empty?
    end

    def reserved_phone?(number)
      digits = number.to_s.gsub(/\D/, "")
      digits = digits.delete_prefix("44").prepend("0") if digits.start_with?("44")
      digits.match?(/\A07700900\d{3}\z/)
    end

    # Real brand names mentioned in text, as written.
    def real_brands_in(text)
      text.to_s.scan(BRAND_PATTERN).uniq
    end

    # Every URL, email address, host name or real brand in free text that isn't reserved.
    def unreserved_names_in(text)
      text = text.to_s
      urls = text.scan(URL_PATTERN).reject { |url| reserved_url?(url.sub(/[.,;:!?)\]]+\z/, "")) }
      emails = text.to_enum(:scan, EMAIL_PATTERN).map { Regexp.last_match }
        .reject { |match| reserved_host?(match[1]) }.map { |match| match[0] }
      without_urls_or_emails = text.gsub(URL_PATTERN, " ").gsub(EMAIL_PATTERN, " ")
      hosts = without_urls_or_emails.scan(BARE_HOST_PATTERN).select { |host| looks_like_host?(host) }
        .reject { |host| reserved_host?(host) }

      (urls + emails + hosts + real_brands_in(text)).uniq
    end

    def looks_like_host?(candidate)
      !FILE_EXTENSIONS.include?(candidate.split(".").last.downcase)
    end
  end
end
