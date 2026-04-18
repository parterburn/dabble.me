class ReplaceFilepickerUrlWithUploadingImageAt < ActiveRecord::Migration[6.1]
  # The legacy `filepicker_url` column was originally used to store a
  # Filestack/Filepicker-hosted image URL. For years it has been repurposed
  # as a single-value "image is uploading" flag (set to a placeholder URL
  # constant or nil). Replace it with a proper nullable timestamp.
  def change
    add_column :entries, :uploading_image_at, :datetime
    remove_column :entries, :filepicker_url, :text
  end
end
