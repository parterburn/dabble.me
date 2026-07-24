require 'rails_helper'

RSpec.describe EntriesController, '#update image persistence', type: :controller do
  include_context 'has all objects'

  let(:original_date) { Date.new(2026, 7, 18) }
  let(:new_date) { Date.new(2026, 7, 17) }
  let(:image_filename) { 'journal-photo.jpg' }

  before do
    paid_user
    paid_entry.update_columns(date: original_date, image: image_filename, body: 'Original body with a photo')
    sign_in paid_user
  end

  def update_entry(attrs)
    # Stub fog interactions that CarrierWave triggers when remove_image is present.
    allow_any_instance_of(ImageUploader).to receive(:relocate_between_dates!).and_return(nil)
    allow_any_instance_of(ImageUploader).to receive(:remove!).and_return(true)
    allow_any_instance_of(ImageUploader).to receive(:blank?).and_return(false)
    fog_file = instance_double(
      CarrierWave::Storage::Fog::File,
      content_type: 'image/jpeg',
      filename: image_filename,
      path: "uploads/development/key/#{image_filename}",
      empty?: false,
      exists?: true,
      delete: true,
      size: 10
    )
    allow_any_instance_of(ImageUploader).to receive(:file).and_return(fog_file)

    put :update, params: {
      id: paid_entry.id,
      entry: {
        entry: attrs.fetch(:entry, paid_entry.body),
        date: attrs.fetch(:date, paid_entry.date).strftime('%B %-d, %Y'),
        remove_image: attrs.fetch(:remove_image, '0')
      }
    }
  end

  it 'keeps the photo when changing the date without toggling remove-photo' do
    expect_any_instance_of(ImageUploader).to receive(:relocate_between_dates!).with(original_date, new_date).and_return(nil)

    update_entry(date: new_date, entry: 'Updated after midnight', remove_image: '0')

    expect(response).to redirect_to(day_entry_path(year: new_date.year, month: new_date.month, day: new_date.day))
    paid_entry.reload
    expect(paid_entry.date).to eq(new_date)
    expect(paid_entry.read_attribute(:image)).to eq(image_filename)
  end

  it 'does not re-download the image via remote_image_url on a normal edit' do
    expect_any_instance_of(Entry).not_to receive(:remote_image_url=)

    update_entry(date: original_date, entry: 'Just editing the text', remove_image: '0')

    expect(response).to redirect_to(day_entry_path(year: original_date.year, month: original_date.month, day: original_date.day))
    paid_entry.reload
    expect(paid_entry.read_attribute(:image)).to eq(image_filename)
  end

  it 'clears the photo when remove_image is checked' do
    update_entry(date: original_date, entry: paid_entry.body, remove_image: '1')

    expect(response).to redirect_to(day_entry_path(year: original_date.year, month: original_date.month, day: original_date.day))
    paid_entry.reload
    expect(paid_entry.read_attribute(:image)).to be_blank
  end
end
