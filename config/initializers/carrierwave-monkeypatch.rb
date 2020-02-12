# frozen_string_literal: true
# Monkey patch for long filenames
# @see https://github.com/carrierwaveuploader/carrierwave/pull/539/files
module CWRemoteFix
  # 255 characters is the max size of a filename in modern filesystems
  # and 100 characters are allocated for versions
  MAX_FILENAME_LENGTH = 255 - 100

  def original_filename
    filename = filename_from_header || filename_from_uri
    mime_type = MIME::Types[file.content_type].first
    unless File.extname(filename).present? || mime_type.blank?
      filename = "#{filename}.#{mime_type.extensions.first}"
    end

    if filename.size > MAX_FILENAME_LENGTH
      extension = (filename =~ /\./) ? filename.split(/\./).last : false
      # 32 for MD5 and 2 for the __ separator
      split_position = MAX_FILENAME_LENGTH - 32 - 2
      # +1 for the . in the extension
      split_position -= (extension.size + 1) if extension
      # Generate an hash from original filename
      hex = Digest::MD5.hexdigest(filename[split_position, filename.size])
      # Create a new name within given limits
      filename = filename[0, split_position] + '__' + hex
      filename << '.' + extension if extension
    end
    # Return original or patched filename
    filename
  end

  def filename_from_uri
    URI.decode(File.basename(file.base_uri.path))
  end  
end

# Monkeypatch downloader class using prepend
CarrierWave::Uploader::Download::RemoteFile.prepend CWRemoteFix
