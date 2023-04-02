class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  skip_before_action :authenticate_user!, only: [:payment_notify]
  skip_before_action :authenticate_admin!, only: [:success, :checkout, :billing, :payment_notify]
  skip_before_action :verify_authenticity_token, only: [:success, :checkout, :billing, :payment_notify]

  def index
    @monthlys = User.pro_only.monthly
    @yearlys =  User.pro_only.yearly

    @monthly_recurring = 0
    @monthlys.includes(:payments).each do |user|
      @monthly_recurring += user.payments.last&.amount.to_f
    end

    @annual_recurring = 0
    @yearlys.includes(:payments).each do |user|
      @annual_recurring += user.payments.last&.amount.to_f
    end

    @mrr = @monthly_recurring.to_i + (@annual_recurring.to_i/12)

    @payments = Payment.includes(:user).all.order("date DESC, id DESC")
    params[:per] ||= 100
    @paginated_payments = Kaminari.paginate_array(@payments).page(params[:page]).per(params[:per])
  end

  def new
    @payment = Payment.new
  end

  def create

    if params[:user_email].present?
      user = User.find_by(email: params[:user_email].downcase)
      params[:payment][:user_id] = user.id if user.present?
    end

    @payment = Payment.create(payment_params)

    if @payment.save
      if user.present? && params["send_thanks"] == 1
        user.update(frequency: user.previous_frequency) if user.previous_frequency.any?
        UserMailer.thanks_for_paying(user).deliver_later
        flash[:notice] = "Payment added successfully & thanks was sent!"
      else
        flash[:notice] = "Payment added successfully!"
      end
      user.update(user_params) if user.present? && user_params[:plan].present?
      redirect_to payments_path
    else
      render 'new'
    end
  end

  def edit
    @payment = Payment.find(params[:id])
  end

  def update
    @payment = Payment.find(params[:id])
    if params[:user_email].present?
      user = User.find_by(email: params[:user_email].downcase)
      params[:payment][:user_id] = user.id if user.present?
    end

    if @payment.update(payment_params)
      user.update(user_params) if user.present? && user_params[:plan].present?
      flash[:notice] = "Payment successfully updated!"
      redirect_to payments_path
    else
      render 'edit'
    end
  end

  def destroy
    @payment = Payment.find(params[:id])
    @payment.destroy
    flash[:notice] = 'Payment deleted successfully.'
    redirect_to payments_path
  end

  def payment_notify
    processed_params = if payhere? && valid_payhere_signature?
      process_payhere
    elsif gumroad?
      process_gumroad
    elsif paypal?
      process_paypal
    end

    if processed_params && @user.present?
      @user.update(processed_params)
      if @user.plan_previous_change&.first == "Free"
        begin # upgrade happened, set frequency back + send thanks
          @user.update(frequency: @user.previous_frequency) if @user.previous_frequency.any?
          # UserMailer.thanks_for_paying(@user).deliver_later
        rescue StandardError => e
          Sentry.set_user(id: @user.id, email: @user.email)
          Sentry.capture_exception(e)
        end
      end
    elsif processed_params && params[:event] != "subscription.cancelled"
      UserMailer.no_user_here(params.permit!).deliver_later
    else
      Sentry.capture_message("Payment notification not processed", level: :info, extra: { params: params })
    end
    head :ok, content_type: 'text/html'
  end

  def checkout
    Stripe.api_key = ENV['STRIPE_API_KEY']
    if current_user.stripe_id? && Stripe::Subscription.list(customer: current_user.stripe_id, status: 'active').data.any?
      redirect_to billing_path
    else
      params = {
        line_items: [{
          price: params['plan'] == "yearly" ? ENV['STRIPE_YEARLY_PLAN'] : ENV['STRIPE_MONTHLY_PLAN'],
          quantity: 1,
        }],
        client_reference_id: current_user.id,
        customer_email: current_user.email,
        mode: 'subscription',
        subscription_data: { metadata: { dabble_id: current_user.id } },
        success_url: "https://#{ENV['MAIN_DOMAIN']}/success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "https://#{ENV['MAIN_DOMAIN']}",
      }
      params = current_user.stripe_id? ? params.merge(customer: current_user.stripe_id) : params
      session = Stripe::Checkout::Session.create(params)
      redirect_to session.url
    end
  end

  def success
    if params[:session_id].present?
      Stripe.api_key = ENV['STRIPE_API_KEY']
      session = Stripe::Checkout::Session.retrieve(params[:session_id])
      if session.present? && session.client_reference_id.present?
        user = User.find(session.client_reference_id)
        if user.present?
          plan = session.amount_total > 30_00 ? "PRO Yearly PayHere" : "PRO Monthly PayHere"
          user.update(stripe_id: session.customer, plan: plan)
        end
      end
    end
    redirect_to root_path
  end

  def billing
    if current_user && current_user.stripe_id.present?
      Stripe.api_key = ENV['STRIPE_API_KEY']

      session = Stripe::BillingPortal::Session.create({
        customer: current_user.stripe_id,
        return_url: "https://dabble.me/settings"
      })

      if session.present?
        redirect_to session.url
      else
        redirect_to "https://billing.stripe.com/p/login/3cs3fp4T0gl2cik7ss?prefilled_email=#{current_user.email}"
      end
    elsif current_user && current_user.plan_type_unlinked == "Stripe"
      redirect_to "https://billing.stripe.com/p/login/3cs3fp4T0gl2cik7ss?prefilled_email=#{current_user.email}"
    elsif current_user && current_user.plan_type_unlinked == "Gumroad"
      redirect_to "https://gumroad.com/login"
    elsif current_user && current_user.plan_type_unlinked == "PayPal"
      redirect_to "https://www.paypal.com/myaccount/autopay/"
    else
      redirect_to "https://dabble.me/subscribe", notice: "You are not subscribed to a plan that can be managed here."
    end
  end

  private

  def gumroad?
    params[:email].present? &&
      params[:seller_id] == ENV['GUMROAD_SELLER_ID'] &&
      params[:product_id] == ENV['GUMROAD_PRODUCT_ID']
  end

  def paypal?
    params[:item_name].present? &&
      params[:item_name].include?('Dabble Me') &&
      params[:payment_status].present? &&
      params[:payment_status] == "Completed" &&
      params[:receiver_id] == ENV['PAYPAL_SELLER_ID']
  end

  def payhere?
    params[:customer].present? &&
      (params[:plan].present? && params[:plan][:name].include?("Dabble Me"))
  end

  def process_payhere
    @user = User.find_by(payhere_id: params[:customer][:id])
    @user ||= User.find_by(email: params[:customer][:email].downcase)

    if params[:event] == "payment.failed"
      # Sentry.capture_message("Failed payment", level: :info, extra: { params: params })
      { payhere_id: params[:customer][:id] }
    elsif params[:event] == "payment.success"
      paid = params[:plan][:qty].present? && params[:plan][:qty].positive? ? params[:plan][:price] * params[:plan][:qty] : params[:plan][:price]
      frequency = params[:plan][:billing_interval] == "month" ? "Monthly" : "Yearly"

      if @user.present? && @user.payments.where("comments ILIKE '%#{frequency}%'").last&.date&.to_date != Date.today
        Payment.create(user_id: @user.id, comments: "PayHere #{frequency} from #{params[:customer][:email]}", date: Time.now.strftime("%Y-%m-%d").to_s, amount: paid)
      end
      { plan: "PRO #{frequency} PayHere", payhere_id:  params[:customer][:id] }
    else # params[:event].in?(["subscription.cancelled", "subscription.created"])
      { payhere_id: params[:customer][:id] }
    end
  end

  def process_gumroad
    @user = User.find_by(gumroad_id: params[:purchaser_id])
    @user ||= User.find_by(email: params[:email].downcase)
    paid = params[:price].to_f / 100
    if params[:recurrence].present?
      frequency = params[:recurrence].titleize
    else
      frequency = paid.to_i > 10 ? 'Yearly' : 'Monthly'
    end
    if @user.present? && @user.payments.count > 0 && Payment.where(user_id: @user.id).last.date.to_date === Time.now.to_date
      # duplicate, don't send
    elsif @user.present?
      Payment.create(user_id: @user.id, comments: "Gumroad #{frequency} from #{params[:email]}", date: Time.now.strftime("%Y-%m-%d").to_s, amount: paid )
    end

    { plan: "PRO #{frequency} Gumroad", gumroad_id:  params[:purchaser_id] }
  end

  def process_paypal
    user_key = params[:item_name].gsub('Dabble Me PRO for ','') if params[:item_name].present?
    @user = User.find_by(user_key: user_key)

    paid = params[:mc_gross]
    frequency = paid.to_i > 10 ? 'Yearly' : 'Monthly'

    if @user.present? && @user.payments.count > 0 && Payment.where(user_id: @user.id).last.date.to_date === Time.now.to_date
      # duplicate webhook, don't save
    elsif @user.present?
      Payment.create(user_id: @user.id, comments: "Paypal #{frequency} from #{params[:payer_email]}", date: Time.now.strftime("%Y-%m-%d").to_s, amount: paid )
    end

    { plan: "PRO #{frequency} PayPal", gumroad_id:  @user&.gumroad_id}
  end

  def payment_params
    params.require(:payment).permit(:amount, :date, :user_id,  :comments)
  end

  def user_params
    params.permit(:plan, :gumroad_id, :payhere_id, :stripe_id)
  end

  def valid_payhere_signature?
    return true if Rails.env.test?
    digest = OpenSSL::Digest.new("sha1")
    expected = OpenSSL::HMAC.hexdigest(digest, ENV["PAYHERE_SHARED_SECRET"].to_s, request.raw_post)

    Rack::Utils.secure_compare(expected, request.headers["HTTP_X_SIGNATURE"])
  end
end
