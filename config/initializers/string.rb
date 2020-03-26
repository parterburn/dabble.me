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
