class String
  JS_ESCAPE_MAP = {
    '\\'    => '\\\\',
    "</"    => '<\/',
    "\r\n"  => '\n',
    "\n"    => '\n',
    "\r"    => '\n',
    '"'     => '\\"',
    "'"     => "\\'",
    ";"     => "%3B",
    "`"     => "\\`",
    "$"     => "\\$"
  }

  JS_ESCAPE_MAP[(+"\342\200\250").force_encoding(Encoding::UTF_8).encode!] = "&#x2028;"
  JS_ESCAPE_MAP[(+"\342\200\251").force_encoding(Encoding::UTF_8).encode!] = "&#x2029;"

  def escape_javascript
    result = self.gsub(/(\\|<\/|\r\n|\342\200\250|\342\200\251|[\n\r"';]|[`]|[$])/u) { |match| JS_ESCAPE_MAP[match] }
    self.html_safe? ? result.html_safe : result
  end
end

# Override and accept forwarded emails as posts: https://github.com/discourse/email_reply_trimmer/blob/8e2bf196f8463da6c756f3a90cc92ab450e0004a/lib/email_reply_trimmer/embedded_email_matcher.rb
class EmbeddedEmailMatcher
  def self.match?(line)
    (EMBEDDED_REGEXES - FORWARDED_EMAIL_REGEXES).any? { |r| line =~ r }
  end
end
