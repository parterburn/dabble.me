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
    a << tag_date.strftime('%b %-d, %Y')
    a.join(" ")
  end

  def distance_of_time_in_words(earlier_date, later_date)
    days = (later_date.to_datetime.to_i - earlier_date.to_datetime.to_i).abs / 86400
    months = ((later_date.year * 12 + later_date.month) - (earlier_date.year * 12 + earlier_date.month)).abs
    if months > 18
      years = (months.to_f / 12).to_f
      rounded_years = "%.2g" % ("%.1f" % years)
      "#{rounded_years} #{'year'.pluralize(years.ceil)}"
    elsif days > 30
      all_days = (later_date.to_date - earlier_date.to_date).to_i
      begin
        earlier_same_day = Date.parse("#{earlier_date.year}-#{earlier_date.month}-#{later_date.day}")
      rescue
        earlier_same_day = Date.parse("#{earlier_date.year}-#{earlier_date.month}-#{earlier_date.end_of_month.day}")
      end
      days_between_months = (later_date.to_date - earlier_same_day).to_i
      extra_days = (all_days - days_between_months).abs
      add_days = extra_days > 0 ? ", #{extra_days} #{'day'.pluralize(extra_days)}" : ""
      "#{months} #{'month'.pluralize(months)}#{add_days}"
    elsif days % 7 == 0
      "#{days/7} #{'week'.pluralize(days/7)}"
    else
      "#{days} #{'day'.pluralize(days)}"
    end
  end
end
