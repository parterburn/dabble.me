require 'rails_helper'

RSpec.describe Entry do
  describe '.count_words' do
    it 'counts whitespace-separated words, ignoring tags and entities' do
      expect(described_class.count_words('<p>Hiking with <b>Sam</b> #Outside</p>')).to eq(4)
      expect(described_class.count_words('<p>Rain &amp; tea</p>')).to eq(2)
      expect(described_class.count_words("<p>One</p><p>two\n three</p>")).to eq(3)
    end

    it 'is zero for bodies without words' do
      expect(described_class.count_words(nil)).to eq(0)
      expect(described_class.count_words('')).to eq(0)
      expect(described_class.count_words('<div><br></div>')).to eq(0)
    end
  end

  it 'stores the word count on save and keeps it current' do
    entry = FactoryBot.create(:entry, body: '<p>three little words</p>')
    expect(entry.reload.word_count).to eq(3)

    entry.update!(body: '<p>two words</p>')
    expect(entry.reload.word_count).to eq(2)
  end

  describe '.hashtags_in' do
    it 'matches Entry#hashtags' do
      body = '<p>#Run then #coffee</p><p>#run2 and #2fast</p>'
      expect(described_class.hashtags_in(body)).to eq(%w[Run coffee run2 2fast])
      expect(described_class.new(body: body).hashtags).to eq(%w[Run coffee run2 2fast])
    end

    it 'is nil without text and empty without tags' do
      expect(described_class.hashtags_in(nil)).to be_nil
      expect(described_class.hashtags_in('')).to be_nil
      expect(described_class.hashtags_in('plain text')).to eq([])
    end
  end
end
