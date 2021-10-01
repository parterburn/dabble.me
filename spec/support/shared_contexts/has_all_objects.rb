shared_context 'has all objects' do
  let(:user) do
    FactoryBot.create(:user)
  end

  let(:paid_user) do
    FactoryBot.create(:user, plan: 'PRO Monthly PayHere', payhere_id: Faker::Number.number(3), gumroad_id: Faker::Number.number(12))
  end

  let(:superuser) do
    FactoryBot.create(:user, plan: 'PRO Forver', email: ENV['ADMIN_EMAILS']&.split(',').first)
  end

  let(:inspiration) do
    Inspiration.create(category: Faker::Lorem.word, body: Faker::Lorem.sentence)
  end

  let(:payment) do
    Payment.create(user_id: paid_user.id, amount: 3.0, comments: 'Monthly', date: Time.now - 800000)
  end

  let(:entry) { FactoryBot.create(:entry, body: Faker::Lorem.paragraph, user: user) }
  let(:not_my_entry) { FactoryBot.create(:entry, body: Faker::Lorem.paragraph) }
end
