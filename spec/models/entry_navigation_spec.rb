require 'rails_helper'

RSpec.describe Entry do
  let(:user) { FactoryBot.create(:user) }

  describe '#next and #previous' do
    it 'returns neighboring entries with SQL order/limit instead of loading the whole collection' do
      older = user.entries.create!(date: Time.utc(2026, 7, 10, 12, 0, 0), body: 'older')
      middle = user.entries.create!(date: Time.utc(2026, 7, 17, 12, 0, 0), body: 'middle')
      newer = user.entries.create!(date: Time.utc(2026, 7, 20, 12, 0, 0), body: 'newer')

      expect(middle.previous).to eq(older)
      expect(middle.next).to eq(newer)
      expect(older.previous).to be_nil
      expect(newer.next).to be_nil
    end
  end

  describe '#hashtags' do
    it 'extracts unique hashtags across paragraph and line-break tags without concatenating adjacent words' do
      entry = Entry.new(body: '<p>First #morning<br>word</p><p>Second #gratitude<br/>#morning #focus</p>')

      expect(entry.hashtags).to eq(%w[morning gratitude focus])
    end

    it 'ignores hashes inside HTML attributes and numeric character references' do
      entry = Entry.new(
        body: '<p> Don&#39;t&#x27;t click <a href="https://example.com#anchor" style="color: #ff0000">here</a> #valid_tag</p>'
      )

      expect(entry.hashtags).to eq(%w[valid_tag])
    end

    it 'does not raise or drop hashtags when an unclosed angle bracket precedes 400+ words across line breaks' do
      filler = (1..410).map { |i| "word#{i}<br>" }.join(' ')
      entry = Entry.new(body: "<p>Started writing <note #{filler} #reflection</p>")

      expect(entry.hashtags).to eq(%w[reflection])
    end

    it 'does not raise or drop hashtags when an unclosed angle bracket precedes 400+ words in a single paragraph' do
      filler = (1..410).map { |i| "word#{i}" }.join(' ')
      entry = Entry.new(body: "<p>Started writing <note #{filler} #reflection</p>")

      expect(entry.hashtags).to eq(%w[reflection])
    end
  end
end
