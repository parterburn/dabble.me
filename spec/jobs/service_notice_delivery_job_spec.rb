require 'rails_helper'

RSpec.describe ServiceNoticeDeliveryJob do
  let!(:user) { FactoryBot.create(:user, send_updates: false) }
  let!(:notice) { ServiceNotice.create!(message: 'We are closing.', sent_on: Date.current, created_at: Time.current) }

  def deliveries
    ActionMailer::Base.deliveries
  end

  before do
    FactoryBot.create(:entry, user: user, body: 'text')
    deliveries.clear
  end

  it 'sends the notice and records it, even to someone who turned updates off' do
    described_class.perform_now(notice.id, user.id)

    expect(deliveries.map(&:subject)).to eq(['Export your Dabble Me journal'])
    expect(deliveries.first.to).to eq([user.email])
    expect(ServiceNoticeDelivery.where(service_notice: notice, user: user).count).to eq(1)
  end

  it 'sends a notice to a person only once' do
    2.times { described_class.perform_now(notice.id, user.id) }

    expect(deliveries.size).to eq(1)
    expect(ServiceNoticeDelivery.count).to eq(1)
  end

  it 'sends a later notice to the same person' do
    later = ServiceNotice.create!(sent_on: Date.current + 1, created_at: Time.current)

    described_class.perform_now(notice.id, user.id)
    described_class.perform_now(later.id, user.id)

    expect(deliveries.size).to eq(2)
  end

  it 'skips someone who deleted their account or entries after it was queued, and a notice that is gone' do
    leaving = FactoryBot.create(:user, deleted_at: Time.current)
    FactoryBot.create(:entry, user: leaving, body: 'text')
    emptied = FactoryBot.create(:user)
    deliveries.clear

    described_class.perform_now(notice.id, leaving.id)
    described_class.perform_now(notice.id, emptied.id)
    described_class.perform_now(notice.id, 0)
    described_class.perform_now(0, user.id)

    expect(deliveries).to be_empty
    expect(ServiceNoticeDelivery.count).to eq(0)
  end

  it 'forgets the delivery when sending fails, so a retry can send it' do
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now).and_raise(Net::ReadTimeout)

    expect { described_class.perform_now(notice.id, user.id) }.to raise_error(Net::ReadTimeout)
    expect(ServiceNoticeDelivery.count).to eq(0)
  end
end
