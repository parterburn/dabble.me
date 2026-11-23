# frozen_string_literal: true

# What a self-registered OAuth client (Oauth::RegistrationsController) may call itself. The
# consent screen shows the name it registered, so without a check anyone could register
# "Claude" or "Dabble Me for iOS", send people a link, and look like the real thing.
#
# - Names are trimmed to MAX_LENGTH, with control and invisible formatting characters (such as
#   right-to-left overrides) removed.
# - A name that uses a known brand is allowed only when every redirect URI is on that brand's
#   domains (ApplicationHelper::OAUTH_KNOWN_APPLICATION_LOGOS) or on this computer (loopback),
#   where a phishing link can't deliver the code to anyone else. Dabble Me's own name has no
#   domains for this: only a local tool, or a known brand's own client, may use it.
module OauthClientNames
  MAX_LENGTH = 60
  DEFAULT_NAME = 'MCP client'
  DABBLE_ME = { pattern: /dabble\s*-?\s*me|\bdabble\b/i, verified_domains: [], alt: 'Dabble Me' }.freeze

  module_function

  def clean(name)
    cleaned = name.to_s.gsub(/\p{Cf}/, '').gsub(/\p{Cc}/, ' ').squish
    cleaned = cleaned[0, MAX_LENGTH].strip
    cleaned.presence || DEFAULT_NAME
  end

  # The brand ("Claude", "Dabble Me") a name claims without the redirect URIs to back it, or nil.
  # A name naming several brands passes when one of them is backed: ChatGPT registering
  # "ChatGPT for Dabble Me" from chatgpt.com is fine.
  def impersonated_brand(name, redirect_uris)
    uris = Array(redirect_uris).flat_map { |uri| uri.to_s.split }.reject(&:blank?)
    claimed = brands.select { |brand| name.to_s.match?(brand[:pattern]) }
    return nil if claimed.empty?
    return nil if claimed.any? { |brand| uris.any? && uris.all? { |uri| backs_brand?(uri, brand[:verified_domains]) } }

    claimed.first[:alt]
  end

  def brands
    ApplicationHelper::OAUTH_KNOWN_APPLICATION_LOGOS + [DABBLE_ME]
  end

  def backs_brand?(raw_uri, domains)
    uri = URI.parse(raw_uri.to_s)
    return true if Mcp::OauthRules.loopback?(uri)
    return false unless uri.scheme.to_s.downcase == 'https'

    host = uri.host.to_s.downcase.delete_suffix('.')
    domains.any? { |domain| host == domain || host.end_with?(".#{domain}") }
  rescue URI::InvalidURIError
    false
  end
end
