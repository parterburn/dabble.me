module EntriesHelper
  def image_code(entry)
    converted_image_url = entry.image_url_cdn
    image_tag converted_image_url, data: { src: converted_image_url }, alt: "#{entry.date_format_short}"
  end

  def format_body(body)
    body = Rinku.auto_link(body, :all, 'target="_blank"')
    sanitize body, tags: %w(strong em a div span ul ol li b i img br p hr), attributes: %w(href style src target)
  end
end
