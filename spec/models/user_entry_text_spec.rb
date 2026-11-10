require 'rails_helper'

# User methods that read entry text. They match in Ruby, never in SQL.
RSpec.describe User do
  let(:user) { FactoryBot.create(:user) }

  def entry_with(body, days_ago: 0)
    FactoryBot.create(:entry, user: user, body: body, date: Date.current - days_ago)
  end

  describe '#past_filter_entry_ids' do
    it 'is nil without a filter' do
      entry_with('anything')
      expect(user.past_filter_entry_ids).to be_nil
    end

    it 'returns entries containing any filter word, ignoring case and blanks' do
      breakup = entry_with('The Breakup was hard', days_ago: 1)
      funeral = entry_with('<p>after the funeral</p>', days_ago: 2)
      kept = entry_with('a good day', days_ago: 3)
      user.update!(past_filter: 'breakup, Funeral, ,')

      expect(user.past_filter_entry_ids).to match_array([breakup.id, funeral.id])
      expect(user.random_entries.to_a).to eq([kept])
    end
  end

  describe '#used_hashtags' do
    before do
      entry_with('<p>#Run in the park</p><p>#coffee</p>', days_ago: 1)
      entry_with('another #run', days_ago: 2)
      entry_with('no tags, just a # sign', days_ago: 3)
    end

    it 'lists every tag use, lowercased' do
      expect(user.used_hashtags(user.entries, false)).to match_array(%w[run coffee run])
    end

    it 'lists unique tags by frequency' do
      expect(user.used_hashtags(user.entries, true)).to eq(%w[run coffee])
    end
  end
end
