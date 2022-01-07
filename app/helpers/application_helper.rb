module ApplicationHelper
  def title(page_title)
    content_for(:title) { page_title.to_s }
  end

  def yield_or_default(section, default = '')
    content_for?(section) ? content_for(section) : default
  end

  def tag_relative_date(tag_date, entry_date)
    a = []
    a << distance_of_time_in_words(tag_date, entry_date)
    if tag_date > entry_date
      a << "from"
    else
      a << "since"
    end
    # a << tag_date.strftime('%b %-d, %Y')
    a << "entry"
    a.join(" ")
  end

  def distance_of_time_in_words(earlier_date, later_date)
    Jekyll::Timeago.timeago(earlier_date, later_date, depth: 2, threshold: 0.05).gsub(" ago", "").gsub("in ", "").gsub("tomorrow", "1 day")
  end
end
