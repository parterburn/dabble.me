# frozen_string_literal: true

# json-schema (pulled in by the `mcp` gem) warns if MultiJSON is left enabled.
Rails.application.config.after_initialize do
  JSON::Validator.use_multi_json = false if defined?(JSON::Validator)
end
