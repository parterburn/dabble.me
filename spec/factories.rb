FactoryBot.define do
  factory :webauthn_credential do
    association :user
    external_id { SecureRandom.hex(16) }
    public_key { SecureRandom.hex(32) }
    nickname { "My MacBook" }
    sign_count { 0 }
  end

  factory :user, class: User do
    email { Faker::Internet.email }
    password { Faker::Internet.password(min_length: 8, max_length: 16) }
    first_name { Faker::Name.first_name }
    last_name { Faker::Name.last_name }
  end

  factory :entry, class: Entry do
    date { DateTime.now }
    user { create(:user) }
  end

  factory :email, class: OpenStruct do
    to { [{ full: Faker::Internet.email, email: Faker::Internet.email, token: 'to_user', host: 'email.com', name: Faker::Name.name }] }
    from { { token: 'from_user', host: 'email.com', email: Faker::Internet.email, full: "#{Faker::Name.name} <#{Faker::Internet.email}>", name: Faker::Name.name } }
    subject { nil }
    body { Faker::Lorem.paragraph }
    attachments {[]}
    vendor_specific { {} }
  end
end
