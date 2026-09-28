require 'rails_helper'

RSpec.describe Search do
  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
  let(:other_user) { FactoryBot.create(:user) }

  def entry_with(body, owner: user, days_ago: 0)
    FactoryBot.create(:entry, user: owner, body: body, date: Date.current - days_ago)
  end

  def results(term)
    described_class.new(user: user, term: term).entries.to_a
  end

  it 'returns no entries for a blank term' do
    entry_with('anything')
    expect(results('')).to be_empty
  end

  it 'matches substrings case-insensitively and only for the owner' do
    mine = entry_with('Went Hiking today')
    entry_with('hiking with friends', owner: other_user)
    expect(results('hiking')).to eq([mine])
  end

  it 'treats LIKE wildcards literally' do
    percent = entry_with('grew 100% this year', days_ago: 1)
    entry_with('grew 100 plants', days_ago: 2)
    expect(results('100%')).to eq([percent])
  end

  it 'matches any term for OR searches' do
    a = entry_with('coffee in the morning', days_ago: 1)
    b = entry_with('tea after lunch', days_ago: 2)
    entry_with('water only', days_ago: 3)
    expect(results('coffee OR tea')).to match_array([a, b])
  end

  it 'matches whole-word exact phrases' do
    hit = entry_with('I love the cat.', days_ago: 1)
    entry_with('concatenate strings', days_ago: 2)
    expect(results('"cat"')).to eq([hit])
  end

  it 'does not raise on regex metacharacters in exact phrases' do
    hit = entry_with('I write c++ code daily', days_ago: 1)
    expect { results('"foo(bar"') }.not_to raise_error
    expect(results('"c++ code"')).to eq([hit])
  end
end
