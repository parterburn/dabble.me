require 'rails_helper'

RSpec.describe Mcp::EntrySearch do
  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
  let(:other_user) { FactoryBot.create(:user) }
  let(:search) { described_class.new(user: user) }

  def entry_with(body, owner: user, days_ago: 0)
    FactoryBot.create(:entry, user: owner, body: body, date: Date.current - days_ago)
  end

  def found(**args)
    search.search(**args)[:entries].map { |entry| entry[:id] }
  end

  it 'matches substrings case-insensitively, newest first, only for the owner' do
    older = entry_with('<p>Went Hiking today #outdoors</p>', days_ago: 3)
    newer = entry_with('hiking again', days_ago: 1)
    entry_with('stayed home', days_ago: 2)
    entry_with('hiking with friends', owner: other_user)

    result = search.search(query: 'HIKING')
    expect(result[:total_matches]).to eq(2)
    expect(result[:entries].map { |entry| entry[:id] }).to eq([newer.id, older.id])
    expect(result[:entries].last[:hashtags]).to eq(['outdoors'])
  end

  it 'supports OR and quoted whole-word phrases' do
    coffee = entry_with('coffee in the morning', days_ago: 1)
    tea = entry_with('tea after lunch', days_ago: 2)
    entry_with('teammates at work', days_ago: 3)

    expect(found(query: 'coffee OR lunch')).to eq([coffee.id, tea.id])
    expect(found(query: '"tea"')).to eq([tea.id])
  end

  it 'treats wildcard characters literally' do
    percent = entry_with('grew 100% this year', days_ago: 1)
    entry_with('grew 100 plants', days_ago: 2)

    expect(found(query: '100%')).to eq([percent.id])
  end

  it 'combines the query with date filters and the limit' do
    entry_with('tea long ago', days_ago: 40)
    recent = entry_with('tea this week', days_ago: 2)
    latest = entry_with('tea today', days_ago: 0)

    since = (Date.current - 7).iso8601
    expect(found(query: 'tea', since: since)).to eq([latest.id, recent.id])
    result = search.search(query: 'tea', since: since, limit: 1)
    expect(result[:total_matches]).to eq(2)
    expect(result[:entries].map { |entry| entry[:id] }).to eq([latest.id])
  end

  it 'analyzes only matching entries' do
    entry_with('tea and #calm thoughts', days_ago: 1)
    entry_with('coffee and #wired thoughts', days_ago: 2)

    result = search.analyze(query: 'tea')
    expect(result[:total_matches]).to eq(1)
    expect(result[:most_used_hashtags]).to eq([{ tag: 'calm', count: 1 }])
  end

  it 'appends Spotify songs after an analysis highlight' do
    entry = entry_with('On repeat all evening', days_ago: 1)
    entry.update_column(:songs, [{ 'spotify_id' => 'track1', 'title' => 'Motion Sickness', 'artists' => ['Phoebe Bridgers'] }])

    highlight = search.analyze[:sample_highlights].find { |row| row[:id] == entry.id }
    expect(highlight[:excerpt]).to eq(
      "On repeat all evening\n\n🎶 [Phoebe Bridgers - Motion Sickness](https://open.spotify.com/track/track1)"
    )
  end

  it 'appends dated tags after an analysis highlight' do
    entry_date = Date.new(2026, 3, 5)
    entry = entry_with('Park day with #Leo', days_ago: 0)
    entry.update!(date: entry_date)
    user.original_hashtags.create!(tag: 'Leo', date: entry_date - (9 * 365 + 2))

    highlight = search.analyze[:sample_highlights].find { |row| row[:id] == entry.id }
    expect(highlight[:excerpt]).to end_with("#Leo (9 years, 2 days)")
  end
end
