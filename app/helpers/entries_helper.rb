module EntriesHelper
  def image_code(entry)
    converted_image_url = entry.display_image_url
    image_tag converted_image_url, data: { src: converted_image_url }, alt: "#{entry.date_format_short}", loading: "lazy"
  end

  def format_body(body)
    return nil unless body.present?

    body = Rinku.auto_link(body, :all, 'target="_blank"')
    sanitize body, tags: %w(strong em a div span ul ol li b i img br p hr u em blockquote), attributes: %w(href style src target)
  end

  # Turns each #tag in an entry's HTML into a link that searches for it, the
  # same tags Entry.hashtags_in finds. Text inside a link and the #fragment of
  # a URL written out in text are left alone.
  def link_hashtags(html)
    return html if html.blank? || !html.include?("#")

    fragment = Entry.html_fragment(html)
    document = fragment.document
    Entry.each_hashtag_node(fragment) do |node, matches|
      text = node.content
      position = 0
      matches.each do |match|
        node.add_previous_sibling(document.create_text_node(text[position...match.begin(0)])) if match.begin(0) > position
        tag = "##{match[1]}"
        node.add_previous_sibling(document.create_element("a", tag, href: search_path(search: { term: tag }), class: "s-entry-hashtag"))
        position = match.end(0)
      end
      node.add_previous_sibling(document.create_text_node(text[position..])) if position < text.length
      node.remove
    end
    fragment.to_html.html_safe
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
