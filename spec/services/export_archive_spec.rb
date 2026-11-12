require 'rails_helper'

RSpec.describe ExportArchive do
  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }
  let(:path) { Pathname(Dir.mktmpdir).join('export.zip').to_s }

  def entry_on(date, body, image: nil)
    entry = FactoryBot.create(:entry, user: user, body: body, date: date)
    entry.update_columns(image: image) if image
    entry
  end

  def unzip
    Zip::File.open(path) { |zip| zip.entries.to_h { |file| [file.name, zip.read(file.name).dup.force_encoding('UTF-8')] } }
  end

  before do
    allow_any_instance_of(described_class).to receive(:image_data) { |_archive, entry| "PHOTO-#{entry.date.day}" }
  end

  it 'writes the journal as Markdown and as a web page in date order, with each photo as a file' do
    entry_on(Time.utc(2026, 3, 2, 12), "<p>Second café day</p>", image: 'beach.JPG')
    entry_on(Time.utc(2026, 3, 1, 12), '<p>First <b>day</b> #start</p>')
    entry_on(Time.utc(2026, 3, 3, 12), '', image: 'only-photo.png')
    FactoryBot.create(:entry, body: 'someone else')

    result = described_class.new(user.entries).write_to(path)
    files = unzip

    expect(result.to_h).to eq(entry_count: 3, image_count: 2, skipped_image_count: 0)
    expect(files.keys).to eq(%w[images/2026-03-02.jpg images/2026-03-03.png journal.md journal.html entries.json])
    expect(files['journal.md']).to eq(
      "# Dabble Me journal\n\n" \
      "## 2026-03-01 (Sunday)\n\nFirst **day** #start\n\n" \
      "## 2026-03-02 (Monday)\n\nSecond café day\n\n![Photo](images/2026-03-02.jpg)\n\n" \
      "## 2026-03-03 (Tuesday)\n\n![Photo](images/2026-03-03.png)\n\n"
    )
    expect(JSON.parse(files['entries.json'])).to eq([
      { 'date' => '2026-03-01', 'body' => '<p>First <b>day</b> #start</p>' },
      { 'date' => '2026-03-02', 'body' => '<p>Second café day</p>', 'image' => 'images/2026-03-02.jpg' },
      { 'date' => '2026-03-03', 'body' => '', 'image' => 'images/2026-03-03.png' }
    ])
    expect(files['images/2026-03-02.jpg']).to eq('PHOTO-2')
    expect(files['journal.md']).not_to include('someone else')

    page = Nokogiri::HTML(files['journal.html'])
    expect(page.css('article h2').map(&:text)).to eq(['March 1, 2026', 'March 2, 2026', 'March 3, 2026'])
    expect(page.css('article img').map { |img| img['src'] }).to eq(%w[images/2026-03-02.jpg images/2026-03-03.png])
    expect(page.at_css('article#2026-03-01 b').text).to eq('day')
    expect(page.at_css('.summary').text).to start_with('3 entries')
    expect(files['journal.html']).not_to include('someone else')
  end

  it 'keeps scripts and styling in an entry out of the web page' do
    entry_on(Time.utc(2026, 3, 1, 12), %(<p onclick="x()" style="position:fixed">Hello</p><script>alert(1)</script><a href="javascript:alert(2)">link</a><a href="https://example.com">ok</a>))

    described_class.new(user.entries).write_to(path)
    article = Nokogiri::HTML(unzip['journal.html']).at_css('article')

    expect(article.to_html).not_to include('script', 'onclick', 'position:fixed', 'javascript:')
    expect(article.at_css('a[href="https://example.com"]').text).to eq('ok')
    expect(article.text).to include('Hello')
  end

  it 'reads entries across batches' do
    stub_const('ExportArchive::BATCH_SIZE', 2)
    5.times { |day| entry_on(Time.utc(2026, 4, day + 1, 12), "day #{day + 1}") }

    described_class.new(user.entries).write_to(path)

    expect(unzip['journal.md'].scan(/^## (\S+)/).flatten).to eq(%w[2026-04-01 2026-04-02 2026-04-03 2026-04-04 2026-04-05])
    expect(Nokogiri::HTML(unzip['journal.html']).css('article').size).to eq(5)
  end

  it 'gives two photos on the same day different names' do
    first = entry_on(Time.utc(2026, 5, 1, 8), 'morning', image: 'a.jpg')
    second = entry_on(Time.utc(2026, 5, 1, 20), 'evening', image: 'b.jpg')

    described_class.new(user.entries).write_to(path)

    expect(unzip.keys).to include('images/2026-05-01.jpg', "images/2026-05-01-#{second.id}.jpg")
    expect(first.id).to be < second.id
  end

  it 'leaves out a photo that cannot be read and keeps going' do
    allow_any_instance_of(described_class).to receive(:image_data).and_return(nil)
    entry_on(Time.utc(2026, 6, 1, 12), 'has a photo', image: 'gone.jpg')

    result = described_class.new(user.entries).write_to(path)

    expect(result.to_h).to eq(entry_count: 1, image_count: 0, skipped_image_count: 1)
    files = unzip
    expect(files.keys).to eq(%w[journal.md journal.html entries.json])
    expect(files.values.join).not_to include('images/')
  end

  it 'writes a valid, empty export when there are no entries' do
    result = described_class.new(user.entries).write_to(path)

    expect(result.entry_count).to eq(0)
    expect(unzip['journal.md']).to eq("# Dabble Me journal\n\n")
    expect(Nokogiri::HTML(unzip['journal.html']).css('article')).to be_empty
    expect(JSON.parse(unzip['entries.json'])).to eq([])
  end
end
