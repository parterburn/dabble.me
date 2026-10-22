# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'HTML5 sanitizer unclosed angle bracket handling and resource bounds' do
  it 'retains Nokogiri::Gumbo finite attribute and tree-depth limits' do
    expect(Nokogiri::Gumbo::DEFAULT_MAX_ATTRIBUTES).to eq(400)
    expect(Nokogiri::Gumbo::DEFAULT_MAX_TREE_DEPTH).to eq(400)
  end

  it 'escapes unclosed angle brackets before HTML5 sanitization so 400+ trailing words do not exceed the attribute limit' do
    filler = (1..410).map { |i| "word#{i}" }.join(' ')
    html = "<p>Started writing <note #{filler} #tag</p>"

    expect(ActionController::Base.helpers.strip_tags(html)).to include('Started writing &lt;note word1')
    expect(ActionController::Base.helpers.strip_tags(html)).to end_with('#tag')
    expect(ActionController::Base.helpers.sanitize(html)).to start_with('<p>Started writing &lt;note word1')
  end

  it 'enforces the finite per-element attribute limit on a real tag with more than 400 attributes' do
    attrs = (1..410).map { |i| "data-item-#{i}=\"#{i}\"" }.join(' ')
    html = "<div #{attrs}>content</div>"

    expect {
      ActionController::Base.helpers.sanitize(html)
    }.to raise_error(ArgumentError, /Attributes per element limit exceeded/)
  end
end
