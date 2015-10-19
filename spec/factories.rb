FactoryGirl.define do
  factory :entry, class: Entry do
    date Time.now
    image_url 'https://dabble.me/favicon-32x32.png'
  end

  factory :email, class: OpenStruct do
    to [{ full: Faker::Internet.email, email: Faker::Internet.email, token: 'to_user', host: 'email.com', name: Faker::Name.name }]
    from({ token: 'from_user', host: 'email.com', email: Faker::Internet.email, full: "#{Faker::Name.name} <#{Faker::Internet.email}>", name: Faker::Name.name })
    subject Faker::Company.catch_phrase
    body Faker::Lorem.paragraph
    attachments {[]}
  end
end
