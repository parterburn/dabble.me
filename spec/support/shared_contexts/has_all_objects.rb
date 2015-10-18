shared_context 'has all objects' do
  let(:user) do
    User.create(email: 'test@dabble.me', password: 'password')
  end

  let(:paid_user) do
    User.create(email: 'paid@dabble.me', password: 'password', plan: 'PRO Monthly Gumroad', gumroad_id: '7777777777')
  end

  let(:superuser) do
    User.create(email: 'paularterburn+env@gmail.com', password: 'password')
  end

  let(:inspiration) do
    Inspiration.create(category: 'Email', body: 'Test Inspiration')
  end

  let(:payment) do
    Payment.create(user_id: paid_user.id, amount: 3.0, comments: 'Monthly', date: Time.now - 800000)
  end

  let(:entry) do
    user.entries.create(
      date: Time.now,
      body: 'Test body for an entry that is mine',
      image_url: 'https://dabble.me/favicon-32x32.png',
      inspiration_id: inspiration.id)
  end

  let(:not_my_entry) do
    Entry.create(
      date: Time.now,
      body: "Test body for an entry that isn't mine",
      image_url: 'https://dabble.me/favicon-32x32.png',
      inspiration_id: inspiration.id)
  end
end
