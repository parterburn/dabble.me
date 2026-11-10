require 'rails_helper'

RSpec.describe Entry::Matcher do
  describe '.parse' do
    it 'returns nil when there is nothing to search for' do
      expect(described_class.parse('')).to be_nil
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse('""')).to be_nil
      expect(described_class.parse(' OR ')).to be_nil
    end

    it 'matches substrings case-insensitively' do
      matcher = described_class.parse('hiking')
      expect(matcher.match?('<p>Went Hiking today</p>')).to be true
      expect(matcher.match?('stayed home')).to be false
    end

    it 'compares wildcard and regex characters literally' do
      expect(described_class.parse('100%').match?('grew 100 plants')).to be false
      expect(described_class.parse('100%').match?('grew 100% this year')).to be true
      expect(described_class.parse('a_c').match?('abc')).to be false
      expect(described_class.parse('c++ (really)').match?('I like C++ (really)')).to be true
    end

    it 'matches any term for OR searches' do
      matcher = described_class.parse('Coffee OR tea')
      expect(matcher.match?('coffee in the morning')).to be true
      expect(matcher.match?('TEA after lunch')).to be true
      expect(matcher.match?('water only')).to be false
    end

    it 'matches quoted phrases only on word boundaries' do
      matcher = described_class.parse('"cat"')
      expect(matcher.match?('I love the Cat.')).to be true
      expect(matcher.match?('<p>cat</p>')).to be true
      expect(matcher.match?('concatenate strings')).to be false
      expect(matcher.match?('cat_food')).to be false
      expect(described_class.parse('"c++ code"').match?('I write c++ code daily')).to be true
      expect(described_class.parse('"foo(bar"').match?('anything')).to be false
    end

    it 'never matches a blank body' do
      expect(described_class.parse('a').match?(nil)).to be false
      expect(described_class.parse('a').match?('')).to be false
    end
  end

  describe 'against a relation' do
    let(:user) { FactoryBot.create(:user) }
    let(:other_user) { FactoryBot.create(:user) }

    def entry_with(body, owner: user, days_ago: 0)
      FactoryBot.create(:entry, user: owner, body: body, date: Date.current - days_ago)
    end

    it 'returns matching ids across batches, scoped to the relation' do
      stub_const('Entry::Matcher::BATCH_SIZE', 2)
      hits = [entry_with('tea one', days_ago: 1), entry_with('tea two', days_ago: 3), entry_with('TEA three', days_ago: 5)]
      entry_with('coffee', days_ago: 2)
      entry_with('tea elsewhere', owner: other_user)

      expect(described_class.parse('tea').ids(user.entries)).to match_array(hits.map(&:id))
    end

    it 'filters to a relation that keeps its order and can be counted' do
      older = entry_with('tea', days_ago: 4)
      newer = entry_with('more tea', days_ago: 1)
      entry_with('coffee', days_ago: 2)

      filtered = described_class.parse('tea').filter(user.entries)
      expect(filtered.to_a).to eq([newer, older])
      expect(filtered.count).to eq(2)
    end

    it 'takes the first matches in the relation order, paging as needed' do
      stub_const('Entry::Matcher::BATCH_SIZE', 2)
      entries = (1..5).map { |n| entry_with(n.odd? ? "tea #{n}" : 'coffee', days_ago: n) }

      expect(described_class.parse('tea').first(user.entries, 2)).to eq([entries[0], entries[2]])
      expect(described_class.parse('tea').first(user.entries, 10)).to eq([entries[0], entries[2], entries[4]])
      expect(described_class.parse('nothing').first(user.entries, 2)).to eq([])
    end
  end
end
