require 'rails_helper'

RSpec.describe Api::HashtagCounts do
  let(:user) { FactoryBot.create(:user) }
  let(:counts) { described_class.new(user, since: Date.current - 30) }

  def entry_with(body, days_ago:)
    FactoryBot.create(:entry, user: user, body: body, date: Date.current - days_ago)
  end

  describe '#recent' do
    before do
      stub_const('Api::HashtagCounts::RECENT_PAGE_SIZE', 2)
      entry_with('#Run this morning', days_ago: 1)
      entry_with('no tags here', days_ago: 2)
      entry_with('#coffee and a #run', days_ago: 3)
      entry_with('#books', days_ago: 4)
      entry_with('#old', days_ago: 60)
    end

    it 'lists tags newest first, in their latest spelling, across pages' do
      expect(counts.recent(10).map { |item| item[:tag] }).to eq(%w[Run coffee books])
    end

    it 'stops reading once it has enough tags' do
      queries = []
      callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('"entries"."body"') }
      ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') do
        expect(counts.recent(1).map { |item| item[:tag] }).to eq(%w[Run])
      end
      expect(queries.size).to eq(1)
    end
  end

  describe '#top' do
    it 'counts each tag once per entry, in its most used spelling' do
      entry_with('#Run #Run', days_ago: 1)
      entry_with('#run', days_ago: 2)
      entry_with('#run and #coffee', days_ago: 3)

      expect(counts.top(10)).to eq([{ tag: 'run', count: 3 }, { tag: 'coffee', count: 1 }])
    end

    it 'breaks a tie between spellings with the newest entry, whichever is written first' do
      entry_with('#outside', days_ago: 5)
      entry_with('#Outside', days_ago: 1)
      entry_with('#Books', days_ago: 2)
      entry_with('#books', days_ago: 4)

      expect(counts.top(10)).to eq([{ tag: 'Books', count: 2 }, { tag: 'Outside', count: 2 }])
    end

    it 'breaks a tie on the same date with the later entry' do
      entry_with('#Tea', days_ago: 1)
      entry_with('#tea', days_ago: 1)

      expect(counts.top(10)).to eq([{ tag: 'tea', count: 2 }])
    end

    it 'counts an entry that spells a tag two ways once, in its first spelling' do
      entry_with('#Run then a #run', days_ago: 1)

      expect(counts.top(10)).to eq([{ tag: 'Run', count: 1 }])
    end
  end
end
