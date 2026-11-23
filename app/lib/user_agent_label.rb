# frozen_string_literal: true

# "Safari" and "Mac" from a browser's User-Agent, for the Sessions list (UserSession). Coarse on
# purpose: the browser family and the OS, no versions. Order matters, since most browsers claim
# to be Safari and Chrome too.
module UserAgentLabel
  BROWSERS = [
    [/Edg(e|A|iOS)?\//, 'Edge'],
    [/OPR\/|Opera/, 'Opera'],
    [/Firefox\/|FxiOS\//, 'Firefox'],
    [/SamsungBrowser\//, 'Samsung Internet'],
    [/CriOS\/|Chrome\/|Chromium\//, 'Chrome'],
    [/Safari\//, 'Safari']
  ].freeze

  OPERATING_SYSTEMS = [
    [/iPhone|iPod/, 'iPhone'],
    [/iPad/, 'iPad'],
    [/Android/, 'Android'],
    [/CrOS/, 'ChromeOS'],
    [/Windows/, 'Windows'],
    [/Macintosh|Mac OS X/, 'Mac'],
    [/Linux/, 'Linux']
  ].freeze

  module_function

  def parse(user_agent)
    agent = user_agent.to_s
    {
      browser: BROWSERS.find { |pattern, _| agent.match?(pattern) }&.last || 'Browser',
      os: OPERATING_SYSTEMS.find { |pattern, _| agent.match?(pattern) }&.last
    }
  end
end
