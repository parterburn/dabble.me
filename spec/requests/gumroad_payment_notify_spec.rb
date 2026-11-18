# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Gumroad payment notifications', type: :request do
  around do |example|
    original_seller = ENV['GUMROAD_SELLER_ID']
    original_product = ENV['GUMROAD_PRODUCT_ID']
    ENV['GUMROAD_SELLER_ID'] = 'test_gumroad_seller'
    ENV['GUMROAD_PRODUCT_ID'] = 'test_gumroad_product'
    example.run
  ensure
    ENV['GUMROAD_SELLER_ID'] = original_seller
    ENV['GUMROAD_PRODUCT_ID'] = original_product
  end

  let(:subscriber) do
    create(:user, plan: 'PRO Yearly Gumroad', gumroad_id: '2222222222')
  end

  before do
    subscriber
    ActionMailer::Base.deliveries.clear
    allow(Sentry).to receive(:capture_message)
    allow(Sentry).to receive(:capture_exception)
  end

  def post_gumroad(short_product_id:, product_id: ENV['GUMROAD_PRODUCT_ID'])
    post '/payment_notify', params: {
      seller_id: ENV['GUMROAD_SELLER_ID'],
      product_id: product_id,
      short_product_id: short_product_id,
      email: subscriber.email,
      price: '3600',
      recurrence: 'yearly',
      purchaser_id: subscriber.gumroad_id,
      resource_name: 'sale'
    }
  end

  it 'acknowledges a non-Dabble short product id and does not record or report it' do
    expect {
      post_gumroad(short_product_id: 'notdabble', product_id: 'another-product')
    }.not_to change { Payment.count }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to be_blank
    expect(subscriber.reload.plan).to eq('PRO Yearly Gumroad')
    expect(subscriber.gumroad_id).to eq('2222222222')
    expect(ActionMailer::Base.deliveries).to be_empty
    expect(Sentry).not_to have_received(:capture_message)
    expect(Sentry).not_to have_received(:capture_exception)
  end

  it 'still records a Dabble Me renewal when the short product id is sFmOD' do
    expect {
      post_gumroad(short_product_id: 'sFmOD')
    }.to change { Payment.count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('text/html')
    expect(response.body).to be_blank
    expect(Payment.last.user_id).to eq(subscriber.id)
    expect(subscriber.reload.plan).to eq('PRO Yearly Gumroad')
    expect(ActionMailer::Base.deliveries.map(&:subject)).not_to include('[REFUND REQUIRED] Payment Without a User')
    expect(Sentry).not_to have_received(:capture_message).with('Payment notification not processed', anything)
  end
end
