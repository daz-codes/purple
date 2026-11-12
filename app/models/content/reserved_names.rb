module Content
  # Content must be fiction only. These are the names reserved for documentation and testing,
  # so they can never point at a real organisation:
  #
  # - Domains (RFC 2606 / RFC 6761): example.com, example.net, example.org and their
  #   subdomains, plus anything under the .example, .test and .invalid top-level domains.
  # - UK phone numbers Ofcom reserves for drama: 07700 900000 to 07700 900999.
  # - Alphanumeric SMS sender IDs (up to 11 characters, no digits-only IDs), which aren't routable.
  module ReservedNames
    RESERVED_SECOND_LEVEL = %w[ example.com example.net example.org ].freeze
    RESERVED_TOP_LEVEL = %w[ example test invalid ].freeze

    URL_PATTERN = %r{\b(?:https?|ftp)://[^\s<>"']+}i
    EMAIL_PATTERN = /\b[A-Z0-9._%+-]+@([A-Z0-9-]+(?:\.[A-Z0-9-]+)+)\b/i
    # Bare host names such as "www.real-bank.com" or "real-bank.co.uk" in running text.
    BARE_HOST_PATTERN = /\b(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+(?:[a-z]{2,24})\b/i
    COMMON_TLDS = %w[
      com net org io co uk gov edu info biz app dev me ly gl us eu de fr ie au ca nz in xyz online shop site ai
    ].freeze

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

      address.match?(/\A(?=.*[A-Za-z])[A-Za-z0-9 ]{1,11}\z/)
    end

    def reserved_phone?(number)
      digits = number.to_s.gsub(/\D/, "")
      digits = digits.delete_prefix("44").prepend("0") if digits.start_with?("44")
      digits.match?(/\A07700900\d{3}\z/)
    end

    # Every URL, email address or host name in free text that isn't reserved.
    def unreserved_names_in(text)
      text = text.to_s
      urls = text.scan(URL_PATTERN).reject { |url| reserved_url?(url.sub(/[.,;:!?)\]]+\z/, "")) }
      emails = text.to_enum(:scan, EMAIL_PATTERN).map { Regexp.last_match }
        .reject { |match| reserved_host?(match[1]) }.map { |match| match[0] }
      without_urls_or_emails = text.gsub(URL_PATTERN, " ").gsub(EMAIL_PATTERN, " ")
      hosts = without_urls_or_emails.scan(BARE_HOST_PATTERN).select { |host| looks_like_host?(host) }
        .reject { |host| reserved_host?(host) }

      (urls + emails + hosts).uniq
    end

    def looks_like_host?(candidate)
      COMMON_TLDS.include?(candidate.split(".").last.downcase)
    end
  end
end
