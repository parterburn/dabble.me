require 'rails_helper'

RSpec.describe AdminHelper, type: :helper do
  let(:user) { FactoryBot.create(:user, plan: 'PRO Monthly PayHere') }

  def payment(comments, **attrs)
    Payment.new(user: user, amount: 3, date: Time.now, comments: comments, **attrs)
  end

  describe '#payment_source' do
    it "links a Stripe webhook payment to its invoice" do
      expect(helper.payment_source(payment('Stripe Monthly from a@b.c', stripe_invoice_id: 'in_123')))
        .to eq ['Stripe invoice', 'https://dashboard.stripe.com/invoices/in_123']
    end

    it "links an older Stripe payment, with no invoice ID, to the user's Stripe customer" do
      user.update_column(:stripe_id, 'cus_123')
      expect(helper.payment_source(payment('Stripe Monthly from a@b.c')))
        .to eq ['Stripe customer', 'https://dashboard.stripe.com/customers/cus_123']
    end

    it 'links Gumroad, PayHere and PayPal payments to their dashboards' do
      expect(helper.payment_source(payment('Gumroad Yearly from a@b.c'))[0]).to eq 'Gumroad'
      expect(helper.payment_source(payment('PayHere Monthly from a@b.c'))[0]).to eq 'PayHere'
      expect(helper.payment_source(payment('Paypal Monthly from a@b.c'))[0]).to eq 'PayPal'
    end

    it "links a manual payment to the user's Stripe customer when there is one" do
      user.update_column(:stripe_id, 'cus_123')
      expect(helper.payment_source(payment('Manual'))[0]).to eq 'Stripe customer'
    end

    it 'links nothing for a manual payment from a user with no Stripe customer' do
      expect(helper.payment_source(payment('Manual'))).to be_nil
    end
  end

  describe '#stripe_dashboard_url' do
    it 'uses the test-mode dashboard when the app runs on a test key' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('STRIPE_API_KEY').and_return('sk_test_abc')
      expect(helper.stripe_dashboard_url('customers/cus_1')).to eq 'https://dashboard.stripe.com/test/customers/cus_1'
    end

    it 'uses the live dashboard otherwise' do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('STRIPE_API_KEY').and_return('sk_live_abc')
      expect(helper.stripe_dashboard_url('customers/cus_1')).to eq 'https://dashboard.stripe.com/customers/cus_1'
    end
  end
end
