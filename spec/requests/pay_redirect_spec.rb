# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Pay redirects', type: :request do
  let(:payment_link) { 'https://buy.stripe.com/test_payment' }

  around do |example|
    previous = ENV['PAYMENT_LINK']
    ENV['PAYMENT_LINK'] = payment_link
    example.run
    ENV['PAYMENT_LINK'] = previous
  end

  it 'redirects /pay to PAYMENT_LINK' do
    get '/pay'

    expect(response).to redirect_to(payment_link)
  end

  it 'redirects /pay/:amount with prefilled_amount in cents' do
    get '/pay/35'

    expect(response).to redirect_to("#{payment_link}?prefilled_amount=3500")
  end

  it 'sends both to the goodbye page once a closing is announced' do
    SiteClosure.announce(closes_on: SiteClosure.today + 30, announced_by: nil)

    get '/pay'
    expect(response).to redirect_to('/goodbye')

    get '/pay/35'
    expect(response).to redirect_to('/goodbye')
  end

  it 'redirects temporarily either way, so a browser asks again after a closing is announced or called off' do
    get '/pay'
    expect(response).to have_http_status(:found)
    get '/pay/35'
    expect(response).to have_http_status(:found)

    SiteClosure.announce(closes_on: SiteClosure.today + 30, announced_by: nil)
    get '/pay'
    expect(response).to have_http_status(:found)
    get '/pay/35'
    expect(response).to have_http_status(:found)

    SiteClosure.reopen!
    get '/pay'
    expect(response).to redirect_to(payment_link)
  end
end
