# frozen_string_literal: true

MCP.configure do |config|
  config.exception_reporter = lambda do |exception, server_context|
    Sentry.capture_exception(exception, extra: server_context)
  end
end
