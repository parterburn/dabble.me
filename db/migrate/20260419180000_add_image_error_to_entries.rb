class AddImageErrorToEntries < ActiveRecord::Migration[6.1]
  # Persist the last image-processing error on the entry so we can surface it
  # to the logged-in user on their next page view. Jobs run async after the
  # request is gone, so `flash` won't reach them; storing the message here
  # gives us something a view can render (and something we can clear when the
  # user dismisses it or the next upload succeeds).
  def change
    add_column :entries, :image_error, :text
  end
end
