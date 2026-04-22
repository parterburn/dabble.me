# frozen_string_literal: true

# Load before `mcp` (alphabetically later) so MultiJSON deprecation is silenced.
begin
  require "json-schema"
  JSON::Validator.use_multi_json = false
rescue LoadError
end
