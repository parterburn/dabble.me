require 'rails_helper'

# A # that's part of a URL is a fragment, not a tag, whether the URL is linked
# or written out in text (Rinku only links it when the entry is shown).
RSpec.describe Entry, '.hashtags_in' do
  it 'skips the fragment of a bare URL' do
    expect(described_class.hashtags_in('<p>#Leo see https://example.com/notes#today</p>')).to eq(%w[Leo])
  end

  it 'skips the fragment of a linked URL' do
    body = '<p>#Leo see <a href="https://example.com/notes#today">https://example.com/notes#today</a></p>'

    expect(described_class.hashtags_in(body)).to eq(%w[Leo])
    expect(described_class.new(body: body).hashtags).to eq(%w[Leo])
  end

  it 'skips text inside any link' do
    expect(described_class.hashtags_in('<p><a href="/notes">#Leo’s page</a> and #Run</p>')).to eq(%w[Run])
  end

  it 'finds tags right next to URLs' do
    body = '<p>https://example.com/a#b, #Leo and (www.example.com/#c) #Run</p>' \
           '<p>https://example.com/notes&nbsp;#coffee</p><p>https://example.com/notes<br>#tea</p>'

    expect(described_class.hashtags_in(body)).to eq(%w[Leo Run coffee tea])
  end

  it 'skips fragments in URLs with any scheme or case' do
    expect(described_class.hashtags_in('<p>HTTPS://EXAMPLE.COM/#top obsidian://open?vault=j#heading</p>')).to eq([])
  end
end
