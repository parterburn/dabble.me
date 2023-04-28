shared_context 'has all objects' do
  let(:user) do
    FactoryBot.create(:user, plan: 'Free')
  end

  let(:free_ai) do
    FactoryBot.create(:user, plan: 'Free', ai_opt_in: true)
  end

  let(:paid_user) do
    FactoryBot.create(:user, plan: 'PRO Monthly PayHere', payhere_id: Faker::Number.number(digits: 3), gumroad_id: Faker::Number.number(digits: 12))
  end

  let(:paid_user_ai) do
    FactoryBot.create(:user, plan: 'PRO Monthly PayHere', payhere_id: Faker::Number.number(digits: 3), gumroad_id: Faker::Number.number(digits: 12), ai_opt_in: true)
  end

  let(:paid_annual_user) do
    FactoryBot.create(:user, plan: 'PRO Yearly PayHere', payhere_id: Faker::Number.number(digits: 3))
  end

  let(:superuser) do
    FactoryBot.create(:user, plan: 'PRO Forver', admin: true)
  end

  let(:inspiration) do
    Inspiration.create(category: Faker::Lorem.word, body: Faker::Lorem.sentence)
  end

  let(:payment) do
    Payment.create(user_id: paid_user.id, amount: 3.0, comments: 'Monthly', date: Time.now - 800000)
  end

  let(:entry) { FactoryBot.create(:entry, body: Faker::Lorem.paragraph, user: user, date: DateTime.now.in_time_zone(user.send_timezone)) }
  let(:not_my_entry) { FactoryBot.create(:entry, body: Faker::Lorem.paragraph) }
end
