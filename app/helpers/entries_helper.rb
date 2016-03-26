module EntriesHelper
  def image_code(entry, max)
    if entry.image.present?
      converted_image_url = entry.image.url
    elsif entry.filepicker_url.include?('filepicker.io')
      converted_image_url = filepicker_image_url(entry.filepicker_url, w: max, h: max, fit: 'max', cache: true, rotate: :exif)
    else
      converted_image_url = entry.filepicker_url
    end
    image_tag converted_image_url, data: { src: converted_image_url }, alt: "#{entry.date_format_short}"
  end
end
