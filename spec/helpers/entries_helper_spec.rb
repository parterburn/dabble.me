require 'rails_helper'

RSpec.describe EntriesHelper, type: :helper do
  describe '#link_hashtags' do
    def linked(html)
      Capybara.string(helper.link_hashtags(html))
    end

    it 'links each #tag to a search for it, keeping the text and markup around it' do
      html = helper.link_hashtags('<p><strong>Big day.</strong> #Leo showered and made eggs with #grandma_jo.</p>')

      expect(html).to include('<a href="/search?search%5Bterm%5D=%23Leo" class="s-entry-hashtag">#Leo</a> showered')
      expect(html).to include('<a href="/search?search%5Bterm%5D=%23grandma_jo" class="s-entry-hashtag">#grandma_jo</a>.</p>')
      expect(html).to start_with('<p><strong>Big day.</strong> ')
      expect(html).to be_html_safe
    end

    it 'finds the same tags as Entry.hashtags_in' do
      body = '<p>#1st time at #2026 #Café #run5k</p>'
      page = linked(body)

      expect(page.all('a.s-entry-hashtag').map(&:text)).to eq(Entry.hashtags_in(body).map { |tag| "##{tag}" })
      expect(page).to have_link('#1st')
      expect(page).not_to have_link('#2026')
    end

    it "leaves text inside an existing link alone" do
      page = linked('<p>See <a href="https://example.com/notes#today">https://example.com/notes#today</a> and #Leo</p>')

      expect(page).to have_link('https://example.com/notes#today', href: 'https://example.com/notes#today')
      expect(page.all('a.s-entry-hashtag').map(&:text)).to eq(['#Leo'])
    end

    it 'keeps escaped text escaped' do
      html = helper.link_hashtags('<p>&lt;script&gt;alert(1)&lt;/script&gt; #Leo</p>')

      expect(html).to include('&lt;script&gt;alert(1)&lt;/script&gt; <a ')
      expect(html).not_to include('<script>')
    end

    it 'returns HTML without a # unchanged' do
      html = '<p>No tags here.</p>'.html_safe
      expect(helper.link_hashtags(html)).to equal(html)
      expect(helper.link_hashtags(nil)).to be_nil
    end
  end
end
