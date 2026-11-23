# frozen_string_literal: true

# What a self-registered OAuth client (Oauth::RegistrationsController) may call itself. The
# consent screen shows the name it registered, so without a check anyone could register
# "Claude", send people a link, and look like the real thing.
#
# - Names are trimmed to MAX_LENGTH, with invisible formatting characters (such as right-to-left
#   overrides and zero-width spaces) removed and control characters turned into spaces.
# - Brand words are found in a folded copy of the name (fold): compatibility forms and accents
#   flattened, look-alike letters mapped (Cyrillic а, capital I for l, 0 for o), and everything
#   but letters and digits dropped, so "ClaudeAI", "Cl-aude", "Ｃｌａｕｄｅ" and "Clаude" all read
#   as "claude".
# - impersonated_brand: a name using a brand is backed only when every redirect URI is on that
#   brand's domains (ApplicationHelper::OAUTH_KNOWN_APPLICATION_LOGOS) or on this computer
#   (loopback), where a phishing link can't deliver the code to anyone else. Dabble Me has no
#   domains for this. The consent screen warns whenever a name isn't backed.
# - refuse_registration?: registration itself is refused only when an unbacked name starts with
#   Claude, ChatGPT, OpenAI, Anthropic, Codex or Notion, the names people would trust on sight.
#   "Acme for Claude" or a client calling itself "Dabble Me" still registers, with the warning.
module OauthClientNames
  MAX_LENGTH = 60
  DEFAULT_NAME = 'MCP client'

  BRANDS = [
    { alt: 'Notion', words: %w[notion], logo: 'Notion' },
    { alt: 'Claude', words: %w[claude anthropic], logo: 'Claude' },
    { alt: 'ChatGPT', words: %w[chatgpt openai codex], logo: 'ChatGPT' },
    { alt: 'Dabble Me', words: %w[dabble], logo: nil }
  ].freeze

  # Look-alikes folded to one letter. i, 1 and | read as l (so "CIaude" matches); brand words
  # are folded the same way before comparing.
  CONFUSABLES = {
    'а' => 'a', 'е' => 'e', 'о' => 'o', 'р' => 'p', 'с' => 'c', 'у' => 'y', 'х' => 'x', 'і' => 'l',
    'ј' => 'j', 'ԁ' => 'd', 'һ' => 'h', 'ո' => 'n', 'α' => 'a', 'ε' => 'e', 'ο' => 'o', 'ρ' => 'p',
    'τ' => 't', 'υ' => 'u', 'ν' => 'v', 'κ' => 'k', 'ι' => 'l', 'ı' => 'l', 'ł' => 'l',
    'i' => 'l', '1' => 'l', '|' => 'l', '!' => 'l', '0' => 'o', '3' => 'e', '5' => 's', '$' => 's', '@' => 'a'
  }.freeze

  module_function

  def clean(name)
    cleaned = name.to_s.gsub(/\p{Cf}/, '').gsub(/\p{Cc}/, ' ').squish
    cleaned = cleaned[0, MAX_LENGTH].strip
    cleaned.presence || DEFAULT_NAME
  end

  def fold(text)
    folded = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').unicode_normalize(:nfkc).downcase
    folded = folded.each_char.map { |char| CONFUSABLES.fetch(char, char) }.join
    folded.gsub(/[^a-z0-9]/, '')
  rescue ArgumentError, Encoding::CompatibilityError
    ''
  end

  # The brands a name uses, in the order of BRANDS.
  def claimed_brands(name)
    folded = fold(name)
    BRANDS.select { |brand| brand[:words].any? { |word| folded.include?(fold(word)) } }
  end

  # The brand ("Claude", "Dabble Me") a name claims without the redirect URIs to back it, or nil.
  # A name naming several brands passes when one of them is backed: ChatGPT registering
  # "ChatGPT for Dabble Me" from chatgpt.com is fine.
  def impersonated_brand(name, redirect_uris)
    claimed = claimed_brands(name)
    return nil if claimed.empty?

    uris = Array(redirect_uris).flat_map { |uri| uri.to_s.split }.reject(&:blank?)
    return nil if claimed.any? { |brand| uris.any? && uris.all? { |uri| backs_brand?(uri, domains_for(brand)) } }

    claimed.first[:alt]
  end

  def refuse_registration?(name, redirect_uris)
    brand = impersonated_brand(name, redirect_uris)
    return false if brand.nil? || brand == 'Dabble Me'

    folded = fold(name)
    BRANDS.find { |b| b[:alt] == brand }[:words].any? { |word| folded.start_with?(fold(word)) }
  end

  def domains_for(brand)
    return [] unless brand[:logo]

    ApplicationHelper::OAUTH_KNOWN_APPLICATION_LOGOS.find { |logo| logo[:alt] == brand[:logo] }&.dig(:verified_domains) || []
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
