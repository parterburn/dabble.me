require 'rails_helper'

RSpec.describe Encryption::Backfill do
  let(:user) { FactoryBot.create(:user, first_name: 'Ann') }
  let(:other_user) { FactoryBot.create(:user, first_name: 'Bo') }
  let(:out) { StringIO.new }

  # A row as it was before encryption: plaintext in every encrypted column.
  def legacy_entry(owner, body, days_ago:)
    entry = FactoryBot.create(:entry, user: owner, body: 'placeholder', date: Date.current - days_ago)
    store_plaintext(entry, 'body', body)
    store_plaintext(entry, 'original_email_body', "raw: #{body}")
    store_plaintext(entry, 'original_email', { headers: { Subject: 'Re: hello' } }.to_json)
    entry
  end

  def make_legacy(owner)
    store_plaintext(owner, 'first_name', owner.first_name)
    store_plaintext(owner, 'user_key', owner.user_key)
    store_plaintext(owner, 'image_key', owner.image_key)
  end

  def backfill(**options)
    described_class.new(out: out, **options)
  end

  let!(:entry) { legacy_entry(user, "<p>café ☃ #tag</p>", days_ago: 1) }
  let!(:empty_entry) { legacy_entry(user, '', days_ago: 2) }
  let!(:other_entry) { legacy_entry(other_user, 'theirs', days_ago: 1) }
  let!(:hashtag) do
    tag = user.original_hashtags.create!(tag: 'placeholder', date: Date.new(2020, 1, 1))
    store_plaintext(tag, 'tag', 'Birthday')
    tag
  end

  before do
    make_legacy(user)
    make_legacy(other_user)
  end

  it 'reports the rows that still hold plaintext' do
    status = backfill.status
    expect(status['Entry'].remaining).to eq(3)
    expect(status['User'].remaining).to eq(2)
    expect(status['Hashtag'].remaining).to eq(1)
  end

  it 'rehearses without writing anything' do
    with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'false') do
      expect(backfill.rehearse['Entry'].checked).to eq(3)
    end
    expect(stored_value(entry, 'body')).to eq("<p>café ☃ #tag</p>")
    expect(backfill.status['Entry'].remaining).to eq(3)
  end

  it 'encrypts every row and leaves every value reading the same' do
    results = backfill.encrypt
    expect(results['Entry'].changed).to eq(3)
    expect(results['User'].changed).to eq(2)
    expect(results['Hashtag'].changed).to eq(1)

    %w[body original_email_body original_email].each do |column|
      expect(ciphertext?(stored_value(entry, column))).to be(true), "#{column} is not ciphertext"
    end
    expect(ciphertext?(stored_value(empty_entry, 'body'))).to be(true)
    expect(ciphertext?(stored_value(user, 'user_key'))).to be(true)
    expect(ciphertext?(stored_value(hashtag, 'tag'))).to be(true)

    reloaded = Entry.find(entry.id)
    expect(reloaded.body).to eq("<p>café ☃ #tag</p>")
    expect(reloaded.original_email_body).to eq("raw: <p>café ☃ #tag</p>")
    expect(reloaded.original_email).to eq('headers' => { 'Subject' => 'Re: hello' })
    expect(Entry.find(empty_entry.id).body).to eq('')
    expect(User.find_by(user_key: user.user_key)).to eq(user)
    expect(User.find(user.id).first_name).to eq('Ann')
    expect(Hashtag.find(hashtag.id).tag).to eq('Birthday')

    expect(backfill.status.values.sum(&:remaining)).to eq(0)
  end

  it 'does not touch timestamps or run callbacks' do
    Entry.where(id: entry.id).update_all(updated_at: 3.days.ago, word_count: 99)
    before = Entry.find(entry.id).updated_at

    backfill.encrypt

    expect(Entry.find(entry.id).updated_at).to eq(before)
    expect(Entry.find(entry.id).word_count).to eq(99)
  end

  it 'changes nothing on a second run' do
    backfill.encrypt
    stored = stored_value(entry, 'body')

    expect(backfill.encrypt.values.sum(&:changed)).to eq(0)
    expect(stored_value(entry, 'body')).to eq(stored)
  end

  it 'can be limited to one account' do
    results = backfill(user_id: user.id).encrypt
    expect(results['Entry'].changed).to eq(2)
    expect(results['User'].changed).to eq(1)

    expect(ciphertext?(stored_value(entry, 'body'))).to be(true)
    expect(stored_value(other_entry, 'body')).to eq('theirs')
    expect(stored_value(other_user, 'first_name')).to eq('Bo')
  end

  it 'refuses to run before ciphertext writes are turned on' do
    with_env('ACTIVE_RECORD_ENCRYPTION_WRITE' => 'false') do
      expect { backfill.encrypt }.to raise_error(described_class::VerificationFailed, /ACTIVE_RECORD_ENCRYPTION_WRITE/)
    end
    expect(stored_value(entry, 'body')).to eq("<p>café ☃ #tag</p>")
  end

  it 'rolls a row back and stops when it does not read back identical' do
    allow_any_instance_of(Entry).to receive(:update_columns).and_wrap_original do |original, values|
      original.call(values.merge(body: 'corrupted'))
    end

    expect { backfill.encrypt }.to raise_error(described_class::VerificationFailed, /rolled back/)
    expect(Entry.unscoped.order(:id).map { |row| stored_value(row, 'body') })
      .to eq(["<p>café ☃ #tag</p>", '', 'theirs'])
  end

  it 'returns every row to plaintext' do
    backfill.encrypt
    results = backfill.decrypt
    expect(results['Entry'].changed).to eq(3)

    expect(stored_value(entry, 'body')).to eq("<p>café ☃ #tag</p>")
    expect(JSON.parse(stored_value(entry, 'original_email'))).to eq('headers' => { 'Subject' => 'Re: hello' })
    expect(stored_value(user, 'user_key')).to eq(user.user_key)
    expect(stored_value(hashtag, 'tag')).to eq('Birthday')
    expect(backfill.status['Entry'].remaining).to eq(3)
  end
end
