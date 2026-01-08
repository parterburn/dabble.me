require 'rails_helper'

describe 'Pages' do
  include_context 'has all objects'

  it 'has correct title for Root page' do
    visit root_path
    expect(page).to have_title 'Dabble me — private email journaling & daily reflection.'
  end

  it 'has correct title for FAQs page' do
    visit support_path
    expect(page).to have_title 'Support — Dabble me.'
  end

  it 'has correct title for Privacy page' do
    visit privacy_path
    expect(page).to have_title 'Privacy Policy — Dabble me.'
  end

  it 'has correct title for Terms page' do
    visit terms_path
    expect(page).to have_title 'Terms of Service — Dabble me.'
  end

  it 'has correct title for Subscribe page (redirects to homepage for non-logged-in users)' do
    visit subscribe_path
    expect(page).to have_title 'Dabble me — private email journaling & daily reflection.'
  end
end
