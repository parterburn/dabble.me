require 'rails_helper'

describe 'Pages' do
  include_context 'has all objects'

  it 'has corect title for Root page' do
    visit root_path
    expect(page).to have_title 'Dabble Me - A free private journal.'
  end

  it 'has correct title for FAQs page' do
    visit faqs_path
    expect(page).to have_title 'Dabble Me FAQs'
  end

  it 'has correct title for Subscribe page' do
    visit subscribe_path
    expect(page).to have_title 'Subscribe to Dabble Me PRO'
  end
end
