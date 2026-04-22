# frozen_string_literal: true

# MCP Inspector and other browser-based dev tools need CORS against localhost.
# Restrict to development only (see Fleetio MCP + Rails guide).
if Rails.env.development?
  Rails.application.config.middleware.insert_before 0, Rack::Cors do
    allow do
      origins '*'
      resource '*', headers: :any, methods: %i[get post delete options]
    end
  end
end
