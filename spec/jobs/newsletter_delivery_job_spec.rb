require 'rails_helper'

RSpec.describe NewsletterDeliveryJob do
  before { stub_const('Newsletter::ROOT', Rails.root.join('spec/fixtures/newsletters')) }

  let!(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }

  def deliveries
    ActionMailer::Base.deliveries
  end

  before { deliveries.clear }

  it 'sends the letter the person qualifies for and records it' do
    described_class.perform_now(user.id, 'sample')

    expect(deliveries.map(&:subject)).to eq(['What is new'])
    expect(NewsletterDelivery.where(user: user).pluck(:newsletter, :variant)).to eq([%w[sample quiet]])
  end

  it 'sends a newsletter to a person only once' do
    2.times { described_class.perform_now(user.id, 'sample') }
    expect(deliveries.size).to eq(1)
    expect(NewsletterDelivery.count).to eq(1)
  end

  it 'skips someone who unsubscribed, downgraded or was deleted after it was queued' do
    user.update_columns(send_updates: false)
    free = FactoryBot.create(:user, plan: 'Free')
    deliveries.clear

    described_class.perform_now(user.id, 'sample')
    described_class.perform_now(free.id, 'sample')
    described_class.perform_now(0, 'sample')

    expect(deliveries).to be_empty
    expect(NewsletterDelivery.count).to eq(0)
  end

  it 'forgets the delivery when sending fails, so a retry can send it' do
    allow_any_instance_of(ActionMailer::MessageDelivery).to receive(:deliver_now).and_raise(Net::ReadTimeout)

    expect { described_class.perform_now(user.id, 'sample') }.to raise_error(Net::ReadTimeout)
    expect(NewsletterDelivery.count).to eq(0)
  end
end
