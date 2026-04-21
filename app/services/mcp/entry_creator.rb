module Mcp
  class EntryCreator
    def initialize(user:)
      @user = user
    end

    # Creates an entry for the given calendar day, or appends to that day's entry when
    # merge_with_existing is true (same behavior as the web "add to this day" flow).
    def create(date_string:, body_text:, merge_with_existing: true)
      date = parse_date(date_string)
      return date if date.is_a?(Hash)

      plain = body_text.to_s.strip
      if plain.blank?
        return { success: false, errors: ['Body cannot be blank'] }
      end

      html_body = format_plain_body(plain)
      existing = find_entry_on_calendar_day(date)

      if existing.present?
        if merge_with_existing
          existing.body = "#{existing.body}<hr>#{html_body}"
          return persist(existing, merged: true)
        end

        return {
          success: false,
          errors: [
            "An entry already exists for #{date.iso8601}. Pass merge_with_existing: true to append, or choose another date."
          ]
        }
      end

      entry = @user.entries.build(date: calendar_day_start(date), body: html_body)
      persist(entry, merged: false)
    end

    private

    # Entries store a datetime; match the user's calendar day (same idea as date-range filters elsewhere).
    def find_entry_on_calendar_day(date)
      day_start = calendar_day_start(date)
      @user.entries.where(date: day_start..day_start.end_of_day).first
    end

    def calendar_day_start(date)
      tz = ActiveSupport::TimeZone[@user.send_timezone] || Time.zone
      tz.local(date.year, date.month, date.day).beginning_of_day
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue ArgumentError
      { success: false, errors: ["Invalid date #{value.inspect}. Use YYYY-MM-DD."] }
    end

    def format_plain_body(plain)
      escaped = ERB::Util.html_escape(plain)
      ActionController::Base.helpers.simple_format(escaped, {}, sanitize: false)
    end

    def persist(entry, merged:)
      if entry.save
        { success: true, merged: merged, entry: serialize(entry) }
      else
        { success: false, errors: entry.errors.full_messages }
      end
    end

    def serialize(entry)
      {
        id: entry.id,
        date: entry.date.to_date.iso8601,
        excerpt: entry.text_body.to_s.squish.truncate(400),
        hashtags: entry.hashtags,
        has_image: entry.image.present?
      }
    end
  end
end
