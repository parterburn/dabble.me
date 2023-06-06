class ImageCollageJob < ActiveJob::Base
  queue_as :default

  def perform(entry_id, urls)
    entry = Entry.where(id: entry_id).first
    return nil unless entry.present?

    filestack_collage_url = collage_from_urls(urls + [entry&.image_url_cdn])
    entry.update(remote_image_url: filestack_collage_url)
  end

  def collage_from_urls(urls)
    urls.compact!
    "https://process.filestackapi.com/#{ENV['FILESTACK_API_KEY']}/collage=a:true,i:auto,f:[#{urls[1..-1].map(&:inspect).join(',')}],w:1200,h:1200,m:10/#{urls.first}"
  end
end
