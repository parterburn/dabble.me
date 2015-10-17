require 'spec_helper'

describe 'Welcome' do
  context 'Index' do
    it "has 'Dabble Me' in title" do
      visit root_path
      expect(page).to have_title 'Dabble Me - A free private journal.'
    end
  end
end
