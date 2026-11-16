require 'rails_helper'

RSpec.describe SiteClosure do
  include ActiveSupport::Testing::TimeHelpers

  let(:admin) { FactoryBot.create(:user, admin: true) }
  let(:today) { described_class.today }

  it 'is neither announced nor closed until an admin announces a date' do
    expect(described_class.current).to be_nil
    expect(described_class.announced?).to be(false)
    expect(described_class.closed?).to be(false)
  end

  it 'is announced but open through its last day, and closed once that day has ended' do
    closure = described_class.announce(closes_on: today, announced_by: admin)

    expect(closure).to be_persisted
    expect(closure.announced_by).to eq(admin)
    expect(described_class.announced?).to be(true)
    expect(described_class.closed?).to be(false)

    closure.update_columns(closes_on: today - 1)
    expect(described_class.closed?).to be(true)
  end

  it 'ends the last day at midnight Pacific time, not UTC' do
    closure = described_class.new(closes_on: Date.new(2027, 3, 1))
    pacific = ActiveSupport::TimeZone[described_class::TIME_ZONE]

    travel_to(pacific.local(2027, 3, 1, 23, 59)) { expect(closure.closed?).to be(false) }
    travel_to(pacific.local(2027, 3, 2, 0, 1)) { expect(closure.closed?).to be(true) }
  end

  it 'keeps one closure, moving its date when announced again' do
    described_class.announce(closes_on: today + 90, announced_by: admin)
    described_class.announce(closes_on: today + 30, announced_by: admin)

    expect(described_class.count).to eq(1)
    expect(described_class.current.closes_on).to eq(today + 30)
  end

  it 'needs a date that is not in the past' do
    expect(described_class.announce(closes_on: nil, announced_by: admin).errors[:closes_on]).to be_present
    expect(described_class.announce(closes_on: today - 1, announced_by: admin).errors[:closes_on]).to include("can't be in the past")
    expect(described_class.announced?).to be(false)
  end

  it 'stays valid after its date has passed, and is not closed without a date' do
    closure = described_class.announce(closes_on: today, announced_by: admin)
    closure.update_columns(closes_on: today - 10)

    expect(closure.reload).to be_valid
    expect(closure.closed?).to be(true)
    expect(described_class.new.closed?).to be(false)
  end

  it 'tells people their journal is deleted 30 days after closing' do
    expect(described_class.new(closes_on: Date.new(2027, 3, 1)).deletes_on).to eq(Date.new(2027, 3, 31))
  end

  it 'reopens when the closing is called off' do
    described_class.announce(closes_on: today, announced_by: admin)
    described_class.reopen!

    expect(described_class.announced?).to be(false)
    expect(described_class.closed?).to be(false)
  end
end
