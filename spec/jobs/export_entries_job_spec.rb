require 'rails_helper'

RSpec.describe ExportEntriesJob do
  include_context 'with export storage'

  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
  let(:export) { user.exports.create! }
  let(:store) { ExportStore.new }

  def deliveries
    ActionMailer::Base.deliveries
  end

  def stored_files
    path = Pathname(Dir.mktmpdir).join('download.zip')
    body = Fog::Storage.new(CarrierWave::Uploader::Base.fog_credentials).get_object(ENV.fetch('AWS_BUCKET'), export.reload.storage_key).body
    path.binwrite(body)
    Zip::File.open(path.to_s) { |zip| zip.entries.to_h { |file| [file.name, zip.read(file.name).dup.force_encoding('UTF-8')] } }
  end

  before do
    FactoryBot.create(:entry, user: user, body: '<p>hiking in March</p>', date: Time.utc(2026, 3, 1, 12))
    FactoryBot.create(:entry, user: user, body: '<p>reading in 2025</p>', date: Time.utc(2025, 7, 1, 12))
    export
    deliveries.clear
  end

  it 'stores the ZIP privately and emails a link, never the file' do
    described_class.perform_now(export.id)
    export.reload

    expect(export.status).to eq('ready')
    expect(export.entry_count).to eq(2)
    expect(export.byte_size).to be > 0
    expect(export.expires_at).to be_within(1.minute).of(7.days.from_now)
    expect(export.storage_key).to start_with("exports/test/#{user.id}/").and end_with('.zip')
    expect(export.storage_key).not_to include('uploads')
    expect(stored_files['journal.md']).to include('hiking in March', 'reading in 2025')

    mail = deliveries.sole
    expect(mail.to).to eq([user.email])
    expect(mail.subject).to eq('Your Dabble Me export is ready')
    expect(mail.attachments).to be_empty
    expect(mail.text_part.body.to_s).to include("/exports/#{export.token}", 'sign in')
    expect(mail.text_part.body.to_s).not_to include('amazonaws', export.storage_key, 'hiking')
  end

  it 'exports one year, or the entries matching a search, and says so in the documents' do
    export.update!(scope: 'year:2026')
    described_class.perform_now(export.id)
    expect(stored_files['journal.md']).to start_with("# Dabble Me journal\n\nEntries from 2026\n\n").and include('hiking in March')
    expect(stored_files['journal.md']).not_to include('reading in 2025')
    expect(Nokogiri::HTML(stored_files['journal.html']).at_css('.subset').text).to eq('Entries from 2026')
    expect(Nokogiri::HTML(stored_files['journal.html']).at_css('title').text).to eq('Dabble Me journal: Entries from 2026')

    other = user.exports.create!(scope: Export.scope_for(search_term: 'reading'), search_term: 'reading')
    described_class.perform_now(other.id)
    expect(other.reload.entry_count).to eq(1)
  end

  it 'leaves the subset line out of an export of everything' do
    described_class.perform_now(export.id)

    expect(stored_files['journal.md']).to start_with("# Dabble Me journal\n\n## ")
    expect(Nokogiri::HTML(stored_files['journal.html']).at_css('.subset')).to be_nil
  end

  it 'still builds an export queued with its year or search as job options' do
    described_class.perform_now(export.id, { 'year' => '2026' })
    expect(stored_files['journal.md']).to include('hiking in March')
    expect(stored_files['journal.md']).not_to include('reading in 2025')
  end

  it 'does nothing for an export that is not waiting to be built' do
    export.update!(status: 'ready')
    described_class.perform_now(export.id)
    described_class.perform_now(0)

    expect(deliveries).to be_empty
    expect(export.reload.storage_key).to be_nil
  end

  it 'keeps a finished export ready when the email about it cannot be sent' do
    allow(UserMailer).to receive(:export_ready).and_raise(Net::SMTPServerBusy.new('try later'))

    described_class.perform_now(export.id)

    expect(export.reload.status).to eq('ready')
    expect(export).to be_downloadable
    expect(deliveries).to be_empty
  end

  it 'marks the export failed and tells the person when it cannot be built' do
    allow_any_instance_of(ExportStore).to receive(:upload).and_raise(Excon::Error::Timeout)

    described_class.perform_now(export.id)

    expect(export.reload.status).to eq('failed')
    expect(deliveries.sole.subject).to eq("We couldn't finish your Dabble Me export")
  end
end
