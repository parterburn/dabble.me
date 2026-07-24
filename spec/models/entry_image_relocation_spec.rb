require 'rails_helper'

RSpec.describe Entry, 'image relocation on date change' do
  include_context 'has all objects'

  let(:original_date) { Date.new(2026, 7, 18) }
  let(:new_date) { Date.new(2026, 7, 17) }
  let(:image_filename) { 'journal-photo.jpg' }
  let(:uploader) { instance_double(ImageUploader) }

  before do
    paid_entry.update_columns(date: original_date, image: image_filename, body: 'Original body with a photo')
    paid_entry.reload
    allow(paid_entry).to receive(:image).and_return(uploader)
  end

  describe '#relocate_image_on_date_change' do
    it 'relocates when the date is changing and a photo is kept' do
      paid_entry.date = new_date
      expect(uploader).to receive(:relocate_between_dates!).with(original_date, new_date)

      paid_entry.send(:relocate_image_on_date_change)
    end

    it 'does nothing when the date is unchanged' do
      paid_entry.body = 'Just editing the text'
      expect(uploader).not_to receive(:relocate_between_dates!)

      paid_entry.send(:relocate_image_on_date_change)
    end

    it 'does nothing when remove_image? is true' do
      paid_entry.date = new_date
      allow(paid_entry).to receive(:remove_image?).and_return(true)
      expect(uploader).not_to receive(:relocate_between_dates!)

      paid_entry.send(:relocate_image_on_date_change)
    end

    it 'does nothing when there is no photo' do
      paid_entry.update_columns(image: nil)
      paid_entry.reload
      allow(paid_entry).to receive(:image).and_return(uploader)
      paid_entry.date = new_date
      expect(uploader).not_to receive(:relocate_between_dates!)

      paid_entry.send(:relocate_image_on_date_change)
    end
  end
end
