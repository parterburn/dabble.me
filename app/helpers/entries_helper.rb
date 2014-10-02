module EntriesHelper

  def image_code(entry)
    url = URI.parse(entry.image_url)
    req = Net::HTTP.new(url.host, url.port)
    req.use_ssl = true if url.scheme == 'https'
    res = req.request_head(url.path)

    if res.code == "200"
      image_tag "https://images1-focus-opensocial.googleusercontent.com/gadgets/proxy?url=#{u entry.image_url}&container=focus&resize_w=800&refresh=2592000", :class => "s-entry-img col-xs-12", :alt => "#{entry.date}"
    else
      ""
    end
  end

end
