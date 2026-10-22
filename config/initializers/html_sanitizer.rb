# frozen_string_literal: true

# Rails 7.1+ switches ActionView's default sanitizer vendor from Rails::HTML4::Sanitizer
# (libxml2) to Rails::HTML5::Sanitizer (Loofah + Nokogiri::Gumbo). Gumbo enforces a
# default limit of 400 attributes per element (Nokogiri::Gumbo::DEFAULT_MAX_ATTRIBUTES),
# and Loofah.html5_fragment does not forward custom parser options.
#
# In journal entries or inbound emails, an unclosed `<word` token or rich pasted HTML can
# cause Gumbo to tokenize more than 400 attributes on a single element and raise
# `ArgumentError: Attributes per element limit exceeded` during `strip_tags` or `sanitize`.
# Setting DEFAULT_MAX_ATTRIBUTES to -1 disables the per-element attribute limit as
# documented by Nokogiri::HTML5 while keeping DEFAULT_MAX_TREE_DEPTH intact.
if defined?(Nokogiri::Gumbo)
  Nokogiri::Gumbo.send(:remove_const, :DEFAULT_MAX_ATTRIBUTES) if Nokogiri::Gumbo.const_defined?(:DEFAULT_MAX_ATTRIBUTES, false)
  Nokogiri::Gumbo.const_set(:DEFAULT_MAX_ATTRIBUTES, -1)
end
