module EntriesHelper
  def image_code(entry)
    converted_image_url = entry.image_url_cdn
    image_tag converted_image_url, data: { src: converted_image_url }, alt: "#{entry.date_format_short}"
  end

  def link_hashtags(body)
    body.gsub(/#([0-9]+[a-zA-Z_]+\w?|[a-zA-Z_]+\w?)/) { |match| link_to match, search_url(host: ENV['MAIN_DOMAIN'], search: {term: "##{$1}"}) }
  end  

  def format_body(body)
    body = link_hashtags(Rinku.auto_link(body, :all, 'target="_blank"'))
    sanitize body, tags: %w(strong em a div span ul ol li b i img br p hr), attributes: %w(href style src target)
  end
end
