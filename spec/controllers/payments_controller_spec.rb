require 'rails_helper'

RSpec.describe PaymentsController, type: :controller do
  include_context 'has all objects'

  # Initiate objects
  before :each do
    user
    superuser
    payment
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
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show Admin Dashboard to superusers' do
      sign_in superuser
      get :index
      expect(response.status).to eq 200
      expect(response.body).to have_content('paid@dabble.me')
    end
  end

  describe 'edit' do
    it 'should redirect to login url if not logged in' do
      get :edit, id: payment.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      get :edit, id: payment.id
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show Payment to superusers' do
      sign_in superuser
      get :edit, id: payment.id
      expect(response.status).to eq 200
      expect(response.body).to have_field('plan', with: paid_user.plan)
      expect(response.body).to have_field('user_email', with: paid_user.email)
      expect(response.body).to have_field('payment_comments', with: payment.comments)
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
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show new Payment to superusers' do
      sign_in superuser
      get :new
      expect(response.status).to eq 200
      expect(response.body).to have_field('plan')
      expect(response.body).to have_field('user_email')
      expect(response.body).to have_field('payment_comments')
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
      expect { post :create, params }.to_not change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      expect { post :create, params }.to_not change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show create new Payment for superusers' do
      sign_in superuser
      post :create, params
      expect { post :create, params }.to change { Payment.count }.by(1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(payments_url)
    end
  end

  describe 'destroy' do
    it 'should redirect to login url if not logged in' do
      expect { delete :destroy, id: payment.id }.to_not change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(new_user_session_url)
    end

    it 'should redirect to past entries path if not superuser' do
      sign_in user
      expect { delete :destroy, id: payment.id }.to_not change { Payment.count }
      expect(response.status).to eq 302
      expect(response).to redirect_to(past_entries_path)
    end

    it 'should show create new Payment for superusers' do
      sign_in superuser
      expect { delete :destroy, id: payment.id }.to change { Payment.count }.by(-1)
      expect(response.status).to eq 302
      expect(response).to redirect_to(payments_url)
    end
  end

  describe 'payment_notify with Gumroad' do
    let(:gumroad_params) do
      {
        seller_id: ENV['GUMROAD_SELLER_ID'],
        product_id: ENV['GUMROAD_PRODUCT_ID'],
        price: '3600',
        recurrence: 'yearly',
        purchaser_id: '1111111111'
      }
    end

    it 'should create a payment for an existing user with email match, but not email' do
      gumroad_params.merge!(email: paid_user.email, purchaser_id: paid_user.gumroad_id + '1')
      expect { post :payment_notify, gumroad_params }.to change { Payment.count }.by(1)
      expect(paid_user.reload.plan).to eq 'PRO Yearly Gumroad'
      expect(paid_user.reload.gumroad_id).to eq gumroad_params[:purchaser_id]
      expect(ActionMailer::Base.deliveries.last.subject).to_not eq 'Thanks for subscribing to Dabble Me PRO!'      
    end

    it 'should create a payment for an existing user with Gumroad ID match, but not email' do
      gumroad_params.merge!(email: 'wrongemail@dabble.me', purchaser_id: paid_user.gumroad_id)
      expect { post :payment_notify, gumroad_params }.to change { Payment.count }.by(1)
      expect(paid_user.reload.plan).to eq 'PRO Yearly Gumroad'
      expect(paid_user.reload.gumroad_id).to eq gumroad_params[:purchaser_id]
      expect(ActionMailer::Base.deliveries.last.subject).to_not eq 'Thanks for subscribing to Dabble Me PRO!'
    end

    it 'should create a payment if Free user is upgrading and email user thanks' do
      gumroad_params.merge!(email: user.email, price: 300, recurrence: 'monthly')
      expect { post :payment_notify, gumroad_params }.to change { Payment.count }.by(1)
      expect(user.reload.plan).to eq 'PRO Monthly Gumroad'
      expect(user.reload.gumroad_id).to eq gumroad_params[:purchaser_id]
      expect(ActionMailer::Base.deliveries.last.to).to eq [user.email]
      expect(ActionMailer::Base.deliveries.last.subject).to eq 'Thanks for subscribing to Dabble Me PRO!'
    end

    it 'should not create a payment if no match' do
      gumroad_params.merge!(email: paid_user.email + 'no', purchaser_id: paid_user.gumroad_id + '1')
      expect { post :payment_notify, gumroad_params }.to_not change { Payment.count }
      expect(paid_user.reload.plan).to eq paid_user.plan
      expect(ActionMailer::Base.deliveries.last.subject).to eq '[REFUND REQUIRED] Payment Without a User'
    end
  end

  describe 'payment_notify with PayPal' do
    let(:paypal_params) do
      {
        payment_status: 'Completed',
        mc_gross: '36.00',
        receiver_id: ENV['PAYPAL_SELLER_ID']
      }
    end

    it 'should create a payment for an existing user with item_name match' do
      paypal_params.merge!(payer_email: paid_user.email, item_name: "Dabble Me PRO for #{paid_user.user_key}")
      expect { post :payment_notify, paypal_params }.to change { Payment.count }.by(1)
      expect(paid_user.reload.plan).to eq 'PRO Yearly PayPal'
      expect(ActionMailer::Base.deliveries.last.subject).to_not eq 'Thanks for subscribing to Dabble Me PRO!'      
    end

    it 'should not create a payment if no match' do
      paypal_params.merge!(payer_email: paid_user.email, item_name: 'Dabble Me PRO for WRONG_KEY')
      expect { post :payment_notify, paypal_params }.to_not change { Payment.count }
      expect(paid_user.reload.plan).to eq paid_user.plan
      expect(ActionMailer::Base.deliveries.last.subject).to eq '[REFUND REQUIRED] Payment Without a User'
    end
  end
end
