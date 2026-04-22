# frozen_string_literal: true

# Removes OAuth/access_token query values from Sentry payloads before upload.
# Complements Rails filter_parameters (logs).
module SentrySensitiveScrubber
  FILTERED = "[FILTERED]"

  SENSITIVE_PARAM_KEYS = %w[
    access_token
    password
    current_password
    password_confirmation
    otp_attempt
    otp_code
  ].freeze

  module_function

  def scrub_event!(event)
    case event
    when Sentry::ErrorEvent
      scrub_error_event!(event)
    when Sentry::TransactionEvent
      scrub_transaction_event!(event)
    end
    event
  end

  def scrub_error_event!(event)
    event.extra = scrub_value(event.extra) if event.extra.present?
    event.message = scrub_string(event.message) if event.message.present?

    scrub_request!(event.request) if event.request

    if event.exception&.values
      event.exception.values.each do |single|
        single.value = scrub_string(single.value) if single.value.present?
      end
    end

    if event.breadcrumbs
      event.breadcrumbs.each do |crumb|
        crumb.data = scrub_value(crumb.data) if crumb.data.present?
        crumb.message = scrub_string(crumb.message) if crumb.message.present?
      end
    end
  end

  def scrub_transaction_event!(event)
    event.contexts = scrub_value(event.contexts) if event.contexts.present?

    event.spans&.each do |span|
      next unless span.is_a?(Hash)

      if span[:description].present?
        span[:description] = scrub_string(span[:description].to_s)
      elsif span["description"].present?
        span["description"] = scrub_string(span["description"].to_s)
      end

      if span[:data].present?
        span[:data] = scrub_value(span[:data])
      elsif span["data"].present?
        span["data"] = scrub_value(span["data"])
      end

      if span[:tags].present?
        span[:tags] = scrub_value(span[:tags])
      elsif span["tags"].present?
        span["tags"] = scrub_value(span["tags"])
      end
    end
  end

  def scrub_request!(req)
    req.url = scrub_string(req.url) if req.url.present?
    req.query_string = scrub_query_string(req.query_string) if req.query_string.present?
    req.data = scrub_value(req.data) if req.data.present?

    if req.headers.present?
      req.headers.each do |key, val|
        next if val.blank?

        if key.to_s.downcase == "authorization"
          req.headers[key] = scrub_authorization_header(val)
        else
          req.headers[key] = scrub_string(val)
        end
      end
    end
  end

  def scrub_value(obj)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), memo|
        key_s = k.to_s.downcase
        memo[k] =
          if sensitive_param_key?(key_s)
            FILTERED
          else
            scrub_value(v)
          end
      end
    when Array
      obj.map { |v| scrub_value(v) }
    when String
      scrub_string(obj)
    else
      obj
    end
  end

  def scrub_string(str)
    return str unless str.is_a?(String)

    out = str.dup
    out.gsub!(/Bearer\s+\S+/i, "Bearer #{FILTERED}")
    out.gsub!(/([?&]access_token=)[^&\s"']+/i, "\\1#{FILTERED}")
    out
  end

  def scrub_query_string(qs)
    scrub_string(qs)
  end

  def scrub_authorization_header(val)
    return val if val.blank?

    scrub_string(val.to_s)
  end

  def sensitive_param_key?(key_s)
    SENSITIVE_PARAM_KEYS.include?(key_s) ||
      key_s.include?("password") ||
      key_s.include?("token") ||
      key_s.include?("secret")
  end
end
