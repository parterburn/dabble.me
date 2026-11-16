require 'rails_helper'

RSpec.describe SendHourlyEntriesWorker do
  it 'sends no journal emails once Dabble Me has closed' do
    SiteClosure.announce(closes_on: SiteClosure.today, announced_by: nil).update_columns(closes_on: SiteClosure.today - 1)
    expect(User).not_to receive(:subscribed_to_emails)

    described_class.new.perform
  end

  it 'keeps sending through the last day' do
    SiteClosure.announce(closes_on: SiteClosure.today, announced_by: nil)
    expect(User).to receive(:subscribed_to_emails).and_call_original

    described_class.new.perform
  end
end
