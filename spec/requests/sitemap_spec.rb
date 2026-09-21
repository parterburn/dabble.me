require 'rails_helper'

RSpec.describe 'public/sitemap.xml' do
  let(:document) { Nokogiri::XML(File.read(Rails.root.join('public', 'sitemap.xml'))) { |config| config.strict } }
  let(:urls) do
    document.remove_namespaces!
    document.xpath('//url').map { |node| { loc: node.at_xpath('loc').text, lastmod: node.at_xpath('lastmod')&.text } }
  end

  it 'is well-formed and lists only canonical https URLs on the primary host' do
    expect(urls).not_to be_empty
    urls.each { |url| expect(url[:loc]).to match(%r{\Ahttps://dabble\.me(/|\z)}) }
    expect(File.read(Rails.root.join('public', 'sitemap.xml'))).not_to include('&#')
  end

  it 'has real lastmod dates that are never in the future' do
    urls.each do |url|
      date = Date.iso8601(url[:lastmod])
      expect(date).to be > Date.new(2020, 1, 1), "#{url[:loc]} has a placeholder lastmod"
      expect(date).to be <= Date.current
    end
  end

  it 'excludes login and sign-up pages' do
    expect(urls.map { |url| url[:loc] }).not_to include(a_string_matching(%r{/users/}))
  end

  it 'only lists routes that exist' do
    urls.each do |url|
      path = URI.parse(url[:loc]).path.presence || '/'
      expect { Rails.application.routes.recognize_path(path) }.not_to raise_error, "#{path} is not routable"
    end
  end
end
