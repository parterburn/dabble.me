require 'rails_helper'

describe 'Pages' do
  include_context 'has all objects'

  it 'has correct title for Root page' do
    visit root_path
    expect(page).to have_title 'Dabble Me — Your private journal.'
  end

  it 'has correct title for FAQs page' do
    visit faqs_path
    expect(page).to have_title 'Dabble Me — Frequently Asked Questions'
  end

  it 'has correct title for Subscribe page' do
    visit subscribe_path
    expect(page).to have_title 'Dabble Me — Pricing'
  end
end
