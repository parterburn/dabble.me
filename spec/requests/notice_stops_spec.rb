require 'rails_helper'

# The "stop further notices" link in a service notice.
RSpec.describe 'Stopping service notices', type: :request do
  let(:user) { FactoryBot.create(:user, first_name: 'Ann') }
  let(:notice) { ServiceNotice.create!(sent_on: Date.current, created_at: Time.current) }
  let(:delivery) { ServiceNoticeDelivery.create!(service_notice: notice, user: user, created_at: Time.current) }

  before { FactoryBot.create(:entry, user: user, body: 'text') }

  it 'shows a page with a button, and stops nothing until it is pressed' do
    get notice_stop_path(token: delivery.stop_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Stop notices like this one', 'For Ann', 'Stop further notices')
    expect(delivery.reload.stopped_at).to be_nil
    expect(ServiceNotice.recipients).to include(user)
  end

  it 'stops further notices on POST, with no login and no CSRF token' do
    ActionController::Base.allow_forgery_protection = true
    post notice_stop_path(token: delivery.stop_token)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("You won't get further notices")
    expect(delivery.reload.stopped_at).to be_present
    expect(ServiceNotice.recipients).not_to include(user)
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it 'keeps the first time someone stopped, however often the link is used' do
    post notice_stop_path(token: delivery.stop_token)
    first = delivery.reload.stopped_at

    post notice_stop_path(token: delivery.stop_token)
    expect(delivery.reload.stopped_at).to eq(first)
  end

  it 'turns away a token that is not a real copy of a notice' do
    [nil, 'nonsense', user.email_settings_token].each do |token|
      post notice_stop_path(token: token)
      expect(response).to redirect_to(root_path)
    end
    expect(ServiceNoticeDelivery.where.not(stopped_at: nil)).to be_empty
  end
end
