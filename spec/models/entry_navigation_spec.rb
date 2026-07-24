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
end
