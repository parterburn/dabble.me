# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HTML5 sanitizer attribute limit configuration' do
  it 'removes the 400 attributes-per-element cap on Nokogiri::Gumbo' do
    expect(Nokogiri::Gumbo::DEFAULT_MAX_ATTRIBUTES).to eq(-1)
    expect(Nokogiri::Gumbo::DEFAULT_MAX_TREE_DEPTH).to eq(400)
  end

  it 'sanitizes and strips tags on fragments with more than 400 attributes on an element' do
    attrs = (1..410).map { |i| "data-item-#{i}=\"#{i}\"" }.join(' ')
    html = "<div #{attrs}><p>Hello <strong>world</strong> #tag</p></div>"

    expect(ActionController::Base.helpers.strip_tags(html)).to eq('Hello world #tag')
    expect(ActionController::Base.helpers.sanitize(html)).to eq('<div><p>Hello <strong>world</strong> #tag</p></div>')
  end
end
