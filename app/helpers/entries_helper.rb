module EntriesHelper

  def image_code(entry,max)
    converted_image_url = filepicker_image_url(entry.image_url, w: max, h: max, fit: 'max', cache: true, rotate: :exif)
    image_tag converted_image_url, :"data-src" => converted_image_url, :alt => "#{entry.date_format_short}"
  end

end
