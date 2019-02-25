shared_context 'has all objects' do
  let(:user) do
    User.create(email: Faker::Internet.email, password: Faker::Internet.password(8), first_name: Faker::Name.first_name, last_name: Faker::Name.last_name)
  end

  let(:paid_user) do
    User.create(email: Faker::Internet.email, password: Faker::Internet.password(8), plan: 'PRO Monthly PayHere', payhere_id: Faker::Number.number(3), gumroad_id: Faker::Number.number(12), first_name: Faker::Name.first_name, last_name: Faker::Name.last_name)
  end

  let(:superuser) do
    User.create(email: ENV.fetch('ADMIN_EMAILS').split(',').first, password: Faker::Internet.password(8))
  end

  let(:inspiration) do
    Inspiration.create(category: Faker::Lorem.word, body: Faker::Lorem.sentence)
  end

  let(:payment) do
    Payment.create(user_id: paid_user.id, amount: 3.0, comments: 'Monthly', date: Time.now - 800000)
  end

  let(:entry) { FactoryBot.create(:entry, body: Faker::Lorem.paragraph, user_id: user.id) }
  let(:not_my_entry) { FactoryBot.create(:entry, body: Faker::Lorem.paragraph) }
end
