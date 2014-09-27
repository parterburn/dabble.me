module EntriesHelper

  def image_code(entry)
    url = URI.parse(entry.image_url)
    req = Net::HTTP.new(url.host, url.port)
    res = req.request_head(url.path)

    if res.code == "200"
      image_tag entry.image_url, :class => "s-entry-img col-xs-12", :alt => "#{entry.date}"
    else
      ""
    end
  end

  def date_formatted(entry)
    entry.date.strftime("%Y-%m-%d") if entry.date.present?
  end

end
