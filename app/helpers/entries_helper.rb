module EntriesHelper

  def image_code(entry,max)
    image_tag filepicker_image_url(entry.image_url, w: max, h: max, fit: 'max', cache: true, rotate: :exif), :alt => "#{entry.date_format_short}"
  end

end
