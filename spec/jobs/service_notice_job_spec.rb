require 'rails_helper'

RSpec.describe ServiceNoticeJob do
  it "queues the notice's emails" do
    notice = ServiceNotice.create!(sent_on: Date.current, created_at: Time.current)
    expect_any_instance_of(ServiceNotice).to receive(:queue_deliveries!)

    described_class.perform_now(notice.id)
  end

  it 'does nothing for a notice that is gone' do
    expect { described_class.perform_now(0) }.not_to raise_error
  end
end
