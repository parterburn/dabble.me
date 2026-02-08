module EntriesHelper
  def image_code(entry)
    converted_image_url = entry.image_url_cdn
    image_tag converted_image_url, data: { src: converted_image_url }, alt: "#{entry.date_format_short}", loading: "lazy"
  end

  def format_body(body)
    return nil unless body.present?

    body = Rinku.auto_link(body, :all, 'target="_blank"')
    sanitize body, tags: %w(strong em a div span ul ol li b i img br p hr u em blockquote), attributes: %w(href style src target data-content)
  end

  def contribution_calendar_data(entries, year)
    start_date = Date.new(year.to_i, 1, 1)
    end_date = Date.new(year.to_i, 12, 31)

    # Create a set of dates that have entries for O(1) lookup
    entry_dates = entries.pluck(:date).map(&:to_date).to_set

    # Generate calendar data
    dates = []
    date = start_date

    while date <= end_date
      dates << {
        date: date,
        has_entry: entry_dates.include?(date),
        day: date.yday
      }
      date += 1.day
    end

    # Post-process to find streaks
    current_streak = []
    dates.each do |d|
      if d[:has_entry]
        current_streak << d
      else
        if current_streak.any?
          streak_length = current_streak.size
          current_streak.each { |day| day[:streak] = streak_length }
          current_streak = []
        end
        d[:streak] = 0
      end
    end
    # Handle the last streak if year ends with an entry
    if current_streak.any?
      streak_length = current_streak.size
      current_streak.each { |day| day[:streak] = streak_length }
    end

    dates
  end
end
