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
end
