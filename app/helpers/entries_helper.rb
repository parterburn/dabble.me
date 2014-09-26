module EntriesHelper

  def image_code(entry)
    #require "net/http"
    url = URI.parse(entry.image_url)
    req = Net::HTTP.new(url.host, url.port)
    res = req.request_head(url.path)

    if res.code == "200"
      image_tag entry.image_url, :class => "s-entry-img", :alt => "#{entry.date}"
    else
      ""
    end

  end

end
