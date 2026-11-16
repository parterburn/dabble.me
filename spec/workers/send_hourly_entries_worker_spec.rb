require 'rails_helper'

RSpec.describe SendHourlyEntriesWorker do
  it 'sends no journal emails once Dabble Me has closed' do
    SiteClosure.announce(closes_on: Date.current, announced_by: nil)
    expect(User).not_to receive(:subscribed_to_emails)

    described_class.new.perform
  end

  it 'keeps sending while a closing is announced but not yet here' do
    SiteClosure.announce(closes_on: Date.current + 30, announced_by: nil)
    expect(User).to receive(:subscribed_to_emails).and_call_original

    described_class.new.perform
  end
end
