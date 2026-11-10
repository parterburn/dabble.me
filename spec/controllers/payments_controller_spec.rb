require 'rails_helper'

RSpec.describe PaymentsController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
    payment
    paid_user
    paid_annual_user
    ActionMailer::Base.deliveries.clear
  end

  # The "[REFUND REQUIRED]" email explains why the payment wasn't recorded.
  def refund_body
    ActionMailer::Base.deliveries.last.body.to_s
  end

  describe 'index' do
    it 'should redirect to login url if not logged in' do
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      get :index
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Admin Dashboard to superusers' do
      sign_in superuser
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content(paid_user.email)
      expect(response.body).to have_content("payment ledger")
      expect(response.body).to have_content("Admin Stats")
      expect(response.body).not_to have_content("Monthly Subs:")
    end

    context 'searching' do
      let!(:annual_payment) { Payment.create!(user: paid_annual_user, amount: 36.0, comments: 'Stripe Yearly from someone', date: Time.now) }
      # A webhook payment whose user was deleted: only the comment has the email.
      let!(:orphan_payment) { Payment.create!(user_id: nil, amount: 5.0, comments: 'Gumroad Monthly from Gone@Example.com', date: Time.now) }

      before { sign_in superuser }

      it "filters by user ID and totals only that user's payments" do
        get :index, params: { user_id: paid_annual_user.id }

        expect(response.body).to have_content("Payments for #{paid_annual_user.email} (ID #{paid_annual_user.id}): 1 for $36.00", normalize_ws: true)
        expect(response.body).not_to have_content(paid_user.email)
      end

      it 'filters by part of an email, matching the user or the comment' do
        get :index, params: { email: 'gone@example' }

        expect(response.body).to have_content("Total payments: 1 for $5.00", normalize_ws: true)
        expect(response.body).to have_content('Gumroad Monthly from Gone@Example.com')
      end

      it 'matches nothing for a user ID that is not a number' do
        get :index, params: { user_id: 'abc' }
        expect(response.body).to have_content('No payments match.')
      end

      it "links each payment's user to that user's payments" do
        get :index
        expect(response.body).to have_link(paid_annual_user.email, href: payments_path(user_id: paid_annual_user.id))
      end
    end
  end

  describe 'edit' do
    it 'should redirect to login url if not logged in' do
      get :edit, params: { id: payment.id }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      get :edit, params: { id: payment.id }
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show Payment to superusers' do
      sign_in superuser
      get :edit, params: { id: payment.id }
      expect(response.status).to eq 200
      expect(response.body).to have_field('plan', with: paid_user.plan)
      expect(response.body).to have_field('user_email', with: paid_user.email)
      expect(response.body).to have_field('payment_comments', with: payment.comments)
    end

    context 'plan dropdown' do
      let(:active_options) do
        ['Keep current plan', 'Free', 'PRO Monthly PayHere (Stripe)', 'PRO Yearly PayHere (Stripe)', 'PRO Forever']
      end

      before { sign_in superuser }

      it "selects a Stripe user's plan and offers only active plans" do
        get :edit, params: { id: payment.id }
        expect(response.body).to have_select('plan', options: active_options, selected: 'PRO Monthly PayHere (Stripe)')
      end

      it "adds a Gumroad user's current plan so saving keeps it" do
        paid_user.update!(plan: 'PRO Yearly Gumroad')
        get :edit, params: { id: payment.id }
        expect(response.body).to have_select('plan', options: active_options + ['PRO Yearly Gumroad'], selected: 'PRO Yearly Gumroad')
      end

      it "adds a PayPal user's current plan so saving keeps it" do
        paid_user.update!(plan: 'PRO Monthly PayPal')
        get :edit, params: { id: payment.id }
        expect(response.body).to have_select('plan', options: active_options + ['PRO Monthly PayPal'], selected: 'PRO Monthly PayPal')
      end
    end
  end

  describe 'new' do
    it 'should redirect to login url if not logged in' do
      get :new
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      get :new
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show new Payment to superusers' do
      sign_in superuser
      get :new
      expect(response.status).to eq 200
      expect(response.body).to have_field('plan')
      expect(response.body).to have_field('user_email')
      expect(response.body).to have_field('payment_comments')
    end

    it "defaults the plan dropdown to keeping the user's plan, with only active plans" do
      sign_in superuser
      get :new
      expect(response.body).to have_select(
        'plan',
        options: ['Keep current plan', 'Free', 'PRO Monthly PayHere (Stripe)', 'PRO Yearly PayHere (Stripe)', 'PRO Forever']
      )
      # Nothing is preselected, so the form posts the blank "Keep current plan".
      expect(response.body).to have_field('plan', with: '')
    end
  end

  describe 'create' do
    let(:params) do
      {
        user_email: paid_user.email,
        payment: {
          amount: 3.0,
          date: Time.now,
          comments: 'Test Payment'
        }
      }
    end

    it 'should redirect to login url if not logged in' do
      expect { post :create, params: params }.not_to change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      expect { post :create, params: params }.not_to change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show create new Payment for superusers' do
      sign_in superuser
      expect { post(:create, params: params) }.to change { Payment.count }.by(1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(payments_url)
    end

    context 'with a plan set and the billing ID fields blank' do
      # The new-payment form has no user to prefill from, so it always posts
      # these fields empty.
      let(:form_params) { params.merge(plan: 'PRO Yearly PayHere', gumroad_id: '', payhere_id: '', stripe_id: '') }

      before do
        sign_in superuser
        paid_user.update!(stripe_id: 'cus_existing')
      end

      it "keeps the user's existing IDs" do
        original_ids = paid_user.slice(:gumroad_id, :payhere_id, :stripe_id)
        expect(original_ids.values).to all(be_present)

        post :create, params: form_params

        paid_user.reload
        expect(paid_user.plan).to eq 'PRO Yearly PayHere'
        expect(paid_user.slice(:gumroad_id, :payhere_id, :stripe_id)).to eq original_ids
      end

      it 'still updates an ID that is filled in' do
        original_payhere_id = paid_user.payhere_id

        post :create, params: form_params.merge(stripe_id: 'cus_new')

        paid_user.reload
        expect(paid_user.plan).to eq 'PRO Yearly PayHere'
        expect(paid_user.stripe_id).to eq 'cus_new'
        expect(paid_user.payhere_id).to eq original_payhere_id
      end
    end

    describe 'send thanks' do
      include ActiveJob::TestHelper

      # A Free user whose schedule was cut to Sundays when they downgraded.
      before do
        user.update_columns(frequency: ['Sun'], previous_frequency: %w[Mon Wed Fri])
        sign_in superuser
      end

      let(:thanks_params) do
        {
          user_email: user.email,
          plan: 'PRO Monthly PayHere',
          payment: { amount: 3.0, date: Time.now, comments: 'Manual payment', send_thanks: '1' }
        }
      end

      it 'emails thanks and restores the previous schedule when checked' do
        expect { post :create, params: thanks_params }
          .to have_enqueued_mail(UserMailer, :thanks_for_paying).with(user)
        expect(user.reload.frequency).to eq %w[Mon Wed Fri]
        expect(user.plan).to eq 'PRO Monthly PayHere'
        expect(flash[:notice]).to eq 'Payment added successfully & thanks was sent!'
      end

      it 'does neither when unchecked' do
        thanks_params[:payment][:send_thanks] = '0'
        expect { post :create, params: thanks_params }
          .not_to have_enqueued_mail(UserMailer, :thanks_for_paying)
        expect(user.reload.frequency).to eq ['Sun']
        expect(user.plan).to eq 'PRO Monthly PayHere'
        expect(flash[:notice]).to eq 'Payment added successfully!'
      end

      it 'finds the user by user_id when no email is given' do
        id_params = thanks_params.except(:user_email).deep_merge(payment: { user_id: user.id })
        expect { post :create, params: id_params }
          .to have_enqueued_mail(UserMailer, :thanks_for_paying).with(user)
        expect(Payment.last.user_id).to eq user.id
        expect(user.reload.frequency).to eq %w[Mon Wed Fri]
        expect(user.plan).to eq 'PRO Monthly PayHere'
      end
    end

    context 'when the User email and User ID fields do not name one user' do
      include ActiveJob::TestHelper

      before { sign_in superuser }

      let(:missing_id) { User.maximum(:id) + 1000 }
      let(:form_params) do
        { plan: 'PRO Yearly PayHere', payment: { amount: 3.0, date: Time.now, comments: 'Manual', send_thanks: '1' } }
      end

      def expect_refused(params, message)
        payments_before = Payment.count
        expect { post :create, params: params }.not_to have_enqueued_mail(UserMailer, :thanks_for_paying)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to have_content(message)
        expect(Payment.count).to eq payments_before
      end

      it 'refuses an email and an ID that belong to different users' do
        params = form_params.merge(user_email: paid_user.email).deep_merge(payment: { user_id: paid_annual_user.id })
        expect_refused(params, "#{paid_user.email} and User ID #{paid_annual_user.id} are different users")
        expect(paid_user.reload.plan).to eq 'PRO Monthly PayHere'
        expect(paid_annual_user.reload.plan).to eq 'PRO Yearly PayHere'
      end

      it 'refuses an email that matches no user' do
        expect_refused(form_params.merge(user_email: 'nobody@example.com'), 'No user has the email nobody@example.com.')
      end

      it 'refuses an ID that matches no user' do
        expect_refused(form_params.deep_merge(payment: { user_id: missing_id }), "No user has the ID #{missing_id}.")
      end

      it 'keeps what was typed, including an unticked Send thanks, when the form comes back' do
        params = form_params.merge(user_email: 'nobody@example.com').deep_merge(payment: { send_thanks: '0' })
        post :create, params: params

        expect(response.body).to have_field('user_email', with: 'nobody@example.com')
        expect(response.body).to have_field('plan', with: 'PRO Yearly PayHere')
        expect(response.body).to have_unchecked_field('payment_send_thanks')
      end

      it 'saves when the email and ID name the same user' do
        params = form_params.merge(user_email: user.email).deep_merge(payment: { user_id: user.id })
        expect { post :create, params: params }.to change { Payment.count }.by(1)
        expect(Payment.last.user_id).to eq user.id
      end
    end
  end

  describe 'update' do
    before do
      sign_in superuser
      paid_user.update!(stripe_id: 'cus_existing')
    end

    # What the edit form posts when nothing is changed: the plan and billing
    # IDs are prefilled from the payment's current user.
    let(:form_params) do
      {
        id: payment.id,
        user_email: paid_user.email,
        plan: paid_user.plan,
        gumroad_id: paid_user.gumroad_id,
        payhere_id: paid_user.payhere_id,
        stripe_id: paid_user.stripe_id,
        payment: { amount: payment.amount, user_id: payment.user_id, comments: payment.comments }
      }
    end

    it "moves the payment to another user without copying the old user's plan or IDs" do
      paid_annual_user.update!(stripe_id: 'cus_paid_annual_user')
      original = paid_annual_user.slice(:plan, :gumroad_id, :payhere_id, :stripe_id)

      patch :update, params: form_params.merge(user_email: paid_annual_user.email)

      expect(response).to redirect_to(payments_url)
      expect(payment.reload.user_id).to eq paid_annual_user.id
      expect(paid_annual_user.reload.slice(:plan, :gumroad_id, :payhere_id, :stripe_id)).to eq original
      expect(flash[:notice]).to include('plan and billing IDs were not changed')
    end

    it 'updates the plan and IDs when the payment stays with its user' do
      patch :update, params: form_params.merge(plan: 'PRO Yearly PayHere', stripe_id: 'cus_new')

      expect(response).to redirect_to(payments_url)
      paid_user.reload
      expect(paid_user.plan).to eq 'PRO Yearly PayHere'
      expect(paid_user.stripe_id).to eq 'cus_new'
      expect(flash[:notice]).to eq 'Payment successfully updated!'
    end

    it 'keeps an existing ID when its field is blank' do
      patch :update, params: {
        id: payment.id,
        user_email: paid_user.email,
        plan: 'PRO Yearly PayHere',
        gumroad_id: paid_user.gumroad_id,
        payhere_id: paid_user.payhere_id,
        stripe_id: '',
        payment: { amount: 3.0, comments: 'Edited' }
      }

      expect(response).to redirect_to(payments_url)
      paid_user.reload
      expect(paid_user.plan).to eq 'PRO Yearly PayHere'
      expect(paid_user.stripe_id).to eq 'cus_existing'
    end

    context 'with the email cleared and only the User ID filled in' do
      let(:id_params) { form_params.merge(user_email: '') }

      it 'finds the user by ID and updates their plan' do
        patch :update, params: id_params.merge(plan: 'PRO Yearly PayHere')

        expect(response).to redirect_to(payments_url)
        expect(paid_user.reload.plan).to eq 'PRO Yearly PayHere'
        expect(flash[:notice]).to eq 'Payment successfully updated!'
      end

      it "moves the payment to another user's ID without copying the old user's plan or IDs" do
        original = paid_annual_user.slice(:plan, :gumroad_id, :payhere_id, :stripe_id)

        patch :update, params: id_params.deep_merge(payment: { user_id: paid_annual_user.id })

        expect(payment.reload.user_id).to eq paid_annual_user.id
        expect(paid_annual_user.reload.slice(:plan, :gumroad_id, :payhere_id, :stripe_id)).to eq original
        expect(flash[:notice]).to eq "Payment moved to #{paid_annual_user.email}. Their plan and billing IDs were not changed; edit the payment again to change them."
      end
    end

    it 'moves the payment by User ID when the prefilled email is left alone' do
      original = paid_annual_user.slice(:plan, :gumroad_id, :payhere_id, :stripe_id)

      patch :update, params: form_params.deep_merge(payment: { user_id: paid_annual_user.id })

      expect(response).to redirect_to(payments_url)
      expect(payment.reload.user_id).to eq paid_annual_user.id
      expect(paid_annual_user.reload.slice(:plan, :gumroad_id, :payhere_id, :stripe_id)).to eq original
      expect(paid_user.reload.stripe_id).to eq 'cus_existing'
      expect(flash[:notice]).to start_with("Payment moved to #{paid_annual_user.email}.")
    end

    context 'when the edit cannot tell which user is meant' do
      let(:missing_id) { User.maximum(:id) + 1000 }

      def expect_refused(params, message)
        patch :update, params: params

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to have_content(message)
        expect(payment.reload.user_id).to eq paid_user.id
        expect(paid_user.reload.plan).to eq 'PRO Monthly PayHere'
      end

      it 'refuses an email and an ID both changed to different users' do
        params = form_params.merge(user_email: user.email, plan: 'PRO Yearly PayHere')
                            .deep_merge(payment: { user_id: paid_annual_user.id })
        expect_refused(params, "#{user.email} and User ID #{paid_annual_user.id} are different users")
        expect(user.reload.plan).to eq 'Free'
        expect(paid_annual_user.reload.plan).to eq 'PRO Yearly PayHere'
      end

      it 'refuses an email that matches no user' do
        expect_refused(form_params.merge(user_email: 'nobody@example.com', plan: 'PRO Yearly PayHere'),
                       'No user has the email nobody@example.com.')
      end

      it 'refuses an ID changed to one that matches no user' do
        expect_refused(form_params.deep_merge(payment: { user_id: missing_id }), "No user has the ID #{missing_id}.")
      end
    end

    it "still saves a payment whose user was deleted when its ID isn't changed" do
      missing_id = User.maximum(:id) + 1000
      payment.update_column(:user_id, missing_id)

      patch :update, params: {
        id: payment.id,
        user_email: '',
        payment: { amount: payment.amount, user_id: missing_id, comments: 'Edited' }
      }

      expect(response).to redirect_to(payments_url)
      expect(payment.reload.comments).to eq 'Edited'
      expect(payment.user_id).to eq missing_id
    end
  end

  describe 'destroy' do
    it 'should redirect to login url if not logged in' do
      expect { delete(:destroy, params: { id: payment.id }) }.not_to change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      expect { delete(:destroy, params: { id: payment.id }) }.not_to change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(entries_path)
    end

    it 'should show create new Payment for superusers' do
      sign_in superuser
      expect { delete(:destroy, params: { id: payment.id }) }.to change { Payment.count }.by(-1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(payments_url)
    end
  end

  describe 'payment_notify with PayHere' do
    let(:payhere_params) do
      {
        customer: {
          id: 156,
          name: "Jack Frost",
          email: "jack@frost.com"
        },
        payment: {
          amount: 30,
          status: "success"
        },
        plan: {
          name: "Dabble Me PRO Yearly",
          billing_interval: "yearly"
        },
        event: "payment.success"
      }
    end

    it 'should create a payment for an existing user with email match, but not id' do
      payhere_params.deep_merge!(customer: { id: Faker::Number.number(digits: 12), email: paid_user.email })
      expect { post :payment_notify, params: payhere_params, as: :json }.to change { Payment.count }.by(1)
      expect(paid_user.reload.plan).to eq 'PRO Yearly PayHere'
      expect(paid_user.reload.payhere_id).to eq payhere_params[:customer][:id].to_s
      expect(ActionMailer::Base.deliveries.size).to eq 0
    end

    it 'should create a payment but not change plan or email user thanks' do
      payhere_params.deep_merge!(customer: { id: paid_annual_user.payhere_id })
      expect { post :payment_notify, params: payhere_params, as: :json }.not_to change {
        paid_annual_user.reload.plan
      }
      expect(ActionMailer::Base.deliveries.size).to eq 0
    end

    it 'should create a payment for an existing user with PayHere ID match, but not email' do
      payhere_params.deep_merge!(customer: { id: paid_user.payhere_id, email: Faker::Internet.email })
      expect { post :payment_notify, params: payhere_params, as: :json }.to change { Payment.count }.by(1)
      expect(paid_user.reload.plan).to eq 'PRO Yearly PayHere'
      expect(paid_user.reload.payhere_id).to eq payhere_params[:customer][:id].to_s
      expect(ActionMailer::Base.deliveries.size).to eq 0
    end

    it 'should create a payment if Free user is upgrading and email user thanks' do
      # A fresh random ID, so this free user can't match a PRO user's
      # payhere_id (the shared context gives those random 12-digit IDs).
      payhere_params.deep_merge!(customer: { id: Faker::Number.number(digits: 12), email: user.email }, payment: { price: 3 }, plan: { billing_interval: "month" })
      expect { post :payment_notify, params: payhere_params, as: :json }.to change { Payment.count }.by(1)
      expect(user.reload.plan).to eq 'PRO Monthly PayHere'
      expect(user.reload.payhere_id).to eq payhere_params[:customer][:id].to_s
      # expect(ActionMailer::Base.deliveries.last.to).to eq [user.email]
      # expect(ActionMailer::Base.deliveries.last.subject).to eq 'Thanks for subscribing to Dabble Me PRO!'
    end

    it 'should not create a payment if no match' do
      payhere_params.deep_merge!(customer: { id: 999999999999, email: "fakeemail@fake.com" })
      expect { post :payment_notify, params: payhere_params, as: :json }.not_to change { Payment.count }
      expect(paid_user.reload.plan).to eq paid_user.plan
      expect(ActionMailer::Base.deliveries.last.subject).to eq '[REFUND REQUIRED] Payment Without a User'
      expect(refund_body).to include('A PayHere notification', 'No account has PayHere customer ID 999999999999 or the email fakeemail@fake.com')
    end
  end

  describe 'payment_notify with Gumroad' do
    around do |example|
      orig_seller = ENV['GUMROAD_SELLER_ID']
      orig_product = ENV['GUMROAD_PRODUCT_ID']
      ENV['GUMROAD_SELLER_ID'] = orig_seller.presence || 'test_gumroad_seller'
      ENV['GUMROAD_PRODUCT_ID'] = orig_product.presence || 'test_gumroad_product'
      example.run
    ensure
      ENV['GUMROAD_SELLER_ID'] = orig_seller
      ENV['GUMROAD_PRODUCT_ID'] = orig_product
    end

    let(:gumroad_params) do
      {
        seller_id: ENV['GUMROAD_SELLER_ID'],
        product_id: ENV['GUMROAD_PRODUCT_ID'],
        price: '3600',
        recurrence: 'yearly',
        purchaser_id: '1111111111'
      }
    end

    let(:refund_subject) { '[REFUND REQUIRED] Payment Without a User' }
    let(:gumroad_user) do
      FactoryBot.create(:user, plan: 'PRO Yearly Gumroad', gumroad_id: '2222222222').tap { ActionMailer::Base.deliveries.clear }
    end

    it 'records a renewal for a Gumroad subscriber matched by purchaser ID' do
      gumroad_params.merge!(email: Faker::Internet.email, purchaser_id: gumroad_user.gumroad_id)
      expect { post :payment_notify, params: gumroad_params, as: :json }.to change { Payment.count }.by(1)
      expect(Payment.last.user_id).to eq gumroad_user.id
      expect(gumroad_user.reload.plan).to eq 'PRO Yearly Gumroad'
      expect(ActionMailer::Base.deliveries.map(&:subject)).not_to include refund_subject
    end

    it 'records a renewal for a Gumroad subscriber matched by email' do
      gumroad_params.merge!(email: gumroad_user.email.upcase, purchaser_id: '3333333333')
      expect { post :payment_notify, params: gumroad_params, as: :json }.to change { Payment.count }.by(1)
      expect(gumroad_user.reload.gumroad_id).to eq '3333333333'
      expect(ActionMailer::Base.deliveries.map(&:subject)).not_to include refund_subject
    end

    it 'keeps the stored purchaser ID when a renewal has none' do
      gumroad_params.merge!(email: gumroad_user.email, purchaser_id: '')
      expect { post :payment_notify, params: gumroad_params, as: :json }.to change { Payment.count }.by(1)
      expect(gumroad_user.reload.gumroad_id).to eq '2222222222'
    end

    it 'restores PRO for a lapsed Gumroad subscriber matched by purchaser ID' do
      gumroad_user.update!(plan: 'Free')
      gumroad_params.merge!(email: gumroad_user.email, purchaser_id: gumroad_user.gumroad_id, price: '400', recurrence: 'monthly')
      expect { post :payment_notify, params: gumroad_params, as: :json }.to change { Payment.count }.by(1)
      expect(gumroad_user.reload.plan).to eq 'PRO Monthly Gumroad'
    end

    it "flags a Free user's first Gumroad purchase instead of upgrading them" do
      gumroad_params.merge!(email: user.email, price: '400', recurrence: 'monthly')
      expect { post :payment_notify, params: gumroad_params, as: :json }.not_to change { Payment.count }
      expect(user.reload.plan).to eq 'Free'
      expect(user.gumroad_id).to be_blank
      expect(ActionMailer::Base.deliveries.last.subject).to eq refund_subject
      expect(refund_body).to include("#{user.email} is on the Free plan and has never paid through Gumroad")
      expect(refund_body).to include("Matched account: #{user.email} (user #{user.id}, Free)", "/admin/users?email=")
    end

    it 'flags a lapsed user matched only by email' do
      gumroad_user.update!(plan: 'Free')
      gumroad_params.merge!(email: gumroad_user.email, purchaser_id: '4444444444')
      expect { post :payment_notify, params: gumroad_params, as: :json }.not_to change { Payment.count }
      expect(gumroad_user.reload.plan).to eq 'Free'
      expect(ActionMailer::Base.deliveries.last.subject).to eq refund_subject
      expect(refund_body).to include('Gumroad purchaser ID on file (2222222222) differs from this one (4444444444)')
    end

    it 'flags a PRO user on another provider, even with a matching purchaser ID' do
      gumroad_params.merge!(email: paid_user.email, purchaser_id: paid_user.gumroad_id)
      expect { post :payment_notify, params: gumroad_params, as: :json }.not_to change { Payment.count }
      expect(paid_user.reload.plan).to eq 'PRO Monthly PayHere'
      expect(ActionMailer::Base.deliveries.last.subject).to eq refund_subject
      expect(refund_body).to include("#{paid_user.email} (matched by Gumroad purchaser ID) is already on the PRO Monthly PayHere plan")
    end

    # find_by(gumroad_id: nil) would match any user who never used Gumroad.
    it 'does not match a user with no purchaser ID when the ping has none' do
      params_without_id = gumroad_params.except(:purchaser_id).merge(email: Faker::Internet.email)
      expect { post :payment_notify, params: params_without_id, as: :json }.not_to change { Payment.count }
      expect(user.reload.plan).to eq 'Free'
      expect(ActionMailer::Base.deliveries.last.subject).to eq refund_subject
      expect(refund_body).to include('No account matches this purchase (Gumroad purchaser ID (none sent)')
      expect(refund_body).not_to include('Matched account')
    end

    it 'should not create a payment if no match' do
      gumroad_params.merge!(email: Faker::Internet.email, purchaser_id: Faker::Number.number(digits: 12))
      expect { post :payment_notify, params: gumroad_params, as: :json }.not_to change { Payment.count }
      expect(paid_user.reload.plan).to eq paid_user.plan
      expect(ActionMailer::Base.deliveries.last.subject).to eq '[REFUND REQUIRED] Payment Without a User'
    end

    it 'rejects Gumroad notifications when GUMROAD_SELLER_ID or GUMROAD_PRODUCT_ID are unset' do
      ENV['GUMROAD_SELLER_ID'] = nil
      ENV['GUMROAD_PRODUCT_ID'] = nil
      expect do
        post :payment_notify, params: { email: user.email, price: '3600', recurrence: 'yearly' }, as: :json
      end.not_to change { Payment.count }
      expect(user.reload.plan).to eq 'Free'
    end
  end

  describe 'payment_notify with PayPal' do
    around do |example|
      orig_paypal = ENV['PAYPAL_SELLER_ID']
      ENV['PAYPAL_SELLER_ID'] = orig_paypal.presence || 'test_paypal_seller'
      example.run
    ensure
      ENV['PAYPAL_SELLER_ID'] = orig_paypal
    end

    let(:paypal_params) do
      {
        payment_status: 'Completed',
        mc_gross: '36.00',
        receiver_id: ENV['PAYPAL_SELLER_ID']
      }
    end

    # Legacy users had image_key copied from user_key by the migration.
    let(:paypal_user) do
      FactoryBot.create(:user, plan: 'PRO Monthly PayPal').tap { |u| u.update_column(:image_key, u.user_key) }
    end

    it 'records a renewal for a legacy PayPal user without changing their plan' do
      paypal_params.merge!(payer_email: paypal_user.email, item_name: "Dabble Me PRO for #{paypal_user.user_key}")
      expect { post :payment_notify, params: paypal_params, as: :json }.to change { Payment.count }.by(1)
      expect(paypal_user.reload.plan).to eq 'PRO Monthly PayPal'
      expect(Payment.last.user_id).to eq paypal_user.id
      # paypal_user is created inside this example, so its welcome email is in deliveries.
      expect(ActionMailer::Base.deliveries.map(&:subject)).not_to include '[REFUND REQUIRED] Payment Without a User'
    end

    it 'keeps matching a legacy PayPal user after they reset their posting address' do
      subscription_key = paypal_user.user_key
      paypal_user.update_column(:user_key, User.generate_unique_key)

      paypal_params.merge!(payer_email: paypal_user.email, item_name: "Dabble Me PRO for #{subscription_key}")
      expect { post :payment_notify, params: paypal_params, as: :json }.to change { Payment.count }.by(1)
      expect(Payment.last.user_id).to eq paypal_user.id
    end

    it 'does not match on a posting address that differs from image_key' do
      paypal_user.update_column(:image_key, User.generate_unique_key)

      paypal_params.merge!(payer_email: paypal_user.email, item_name: "Dabble Me PRO for #{paypal_user.user_key}")
      expect { post :payment_notify, params: paypal_params, as: :json }.not_to change { Payment.count }
    end

    it 'does not upgrade a free user even when the key matches' do
      paypal_params.merge!(payer_email: user.email, item_name: "Dabble Me PRO for #{user.image_key}")
      expect { post :payment_notify, params: paypal_params, as: :json }.not_to change { Payment.count }
      expect(user.reload.plan).to eq 'Free'
      expect(ActionMailer::Base.deliveries.last.subject).to eq '[REFUND REQUIRED] Payment Without a User'
      expect(refund_body).to include("#{user.email} has this subscription key (#{user.image_key}) but is on the Free plan, not PRO Monthly PayPal")
    end

    it 'does not record a payment for a PRO user on another plan' do
      paypal_params.merge!(payer_email: paid_user.email, item_name: "Dabble Me PRO for #{paid_user.image_key}")
      expect { post :payment_notify, params: paypal_params, as: :json }.not_to change { Payment.count }
      expect(paid_user.reload.plan).to eq 'PRO Monthly PayHere'
    end

    it 'should not create a payment if no match' do
      paypal_params.merge!(payer_email: paid_user.email, item_name: 'Dabble Me PRO for WRONG_KEY')
      expect { post :payment_notify, params: paypal_params, as: :json }.not_to change { Payment.count }
      expect(paid_user.reload.plan).to eq paid_user.plan
      expect(ActionMailer::Base.deliveries.last.subject).to eq '[REFUND REQUIRED] Payment Without a User'
      expect(refund_body).to include('A PayPal notification', 'No account has the subscription key WRONG_KEY', 'refund it in PayPal')
    end
  end

  describe 'GET #success' do
    it 'does not upgrade the user when the Stripe Checkout Session is unpaid' do
      sign_in user
      unpaid_session = OpenStruct.new(
        id: 'cs_test_unpaid',
        status: 'open',
        payment_status: 'unpaid',
        client_reference_id: user.id.to_s,
        customer: 'cus_test_123',
        amount_total: 3600
      )
      allow(Stripe::Checkout::Session).to receive(:retrieve).with('cs_test_unpaid').and_return(unpaid_session)

      get :success, params: { session_id: 'cs_test_unpaid' }

      expect(response).to redirect_to(root_path)
      expect(user.reload.plan).to eq('Free')
      expect(user.stripe_id).to be_nil
    end

    it 'does not upgrade when client_reference_id belongs to a different user' do
      sign_in user
      other_session = OpenStruct.new(
        id: 'cs_test_other',
        status: 'complete',
        payment_status: 'paid',
        client_reference_id: paid_user.id.to_s,
        customer: 'cus_test_other',
        amount_total: 3600
      )
      allow(Stripe::Checkout::Session).to receive(:retrieve).with('cs_test_other').and_return(other_session)

      get :success, params: { session_id: 'cs_test_other' }

      expect(user.reload.plan).to eq('Free')
    end

    it 'upgrades current_user when the Checkout Session is complete and paid' do
      sign_in user
      paid_session = OpenStruct.new(
        id: 'cs_test_paid',
        status: 'complete',
        payment_status: 'paid',
        client_reference_id: user.id.to_s,
        customer: 'cus_test_paid',
        amount_total: 3600
      )
      allow(Stripe::Checkout::Session).to receive(:retrieve).with('cs_test_paid').and_return(paid_session)

      get :success, params: { session_id: 'cs_test_paid' }

      expect(user.reload.plan).to eq('PRO Yearly PayHere')
      expect(user.stripe_id).to eq('cus_test_paid')
    end
  end
end
