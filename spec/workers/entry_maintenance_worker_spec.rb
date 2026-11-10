require 'rails_helper'

RSpec.describe EntryMaintenanceWorker do
  let(:user) { FactoryBot.create(:user) }

  def entry_with(body, days_ago:)
    FactoryBot.create(:entry, user: user, body: body, date: Date.current - days_ago)
  end

  it 'deletes entries with no image and no body, and nothing else' do
    blank = entry_with('', days_ago: 1)
    null_body = entry_with(nil, days_ago: 2)
    markup_only = entry_with('<div><br></div>', days_ago: 3)
    written = entry_with('a real entry', days_ago: 4)
    photo_only = entry_with('', days_ago: 5)
    photo_only.update_columns(image: 'photo.jpg')

    described_class.new.perform

    expect(Entry.where(id: [blank.id, null_body.id])).to be_empty
    expect(Entry.where(id: [markup_only.id, written.id, photo_only.id]).count).to eq(3)
  end

  it 'keeps a written entry whose word count is missing, and fills it in' do
    entry = entry_with('four words right here', days_ago: 1)
    entry.update_columns(word_count: nil)

    described_class.new.perform

    expect(entry.reload.word_count).to eq(4)
  end
end
