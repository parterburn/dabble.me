# frozen_string_literal: true

# Rails 7.1+ switches ActionView's default sanitizer vendor from Rails::HTML4::Sanitizer
# (libxml2) to Rails::HTML5::Sanitizer (Loofah + Nokogiri::Gumbo). In the WHATWG HTML5
# tokenizer, an unclosed `<word` token in user prose (such as `<sigh` or `<note`) starts
# an HTML tag that is not closed by a subsequent `<`, causing every following
# whitespace-separated word before the next `>` to be parsed as an attribute name on that
# element. When more than Nokogiri::Gumbo::DEFAULT_MAX_ATTRIBUTES (400) words follow,
# Gumbo raises `ArgumentError: Attributes per element limit exceeded`.
#
# Escape bare `<` characters that are not closed by `>` before the next `<` or end-of-input
# prior to HTML5 fragment parsing, while keeping Nokogiri::Gumbo's finite attribute and
# tree-depth limits intact for untrusted HTML.
if defined?(Rails::HTML::Concern::Parser::HTML5)
  module Html5UnclosedAngleBracketNormalizer
    UNCLOSED_ANGLE_BRACKET_REGEX = /<(?=[^<>]*(?:<|\z))/

    def parse_fragment(html)
      super(html.to_s.gsub(UNCLOSED_ANGLE_BRACKET_REGEX, '&lt;'))
    end
  end

  Rails::HTML::Concern::Parser::HTML5.prepend(Html5UnclosedAngleBracketNormalizer)
end
