class PaymentsController < ApplicationController
  before_action :authenticate_user!
  before_filter :require_permission
  
  skip_before_filter :authenticate_user!, :only => [:payment_notify]
  skip_before_filter :require_permission, :only => [:payment_notify]
  skip_before_filter :verify_authenticity_token, :only => [:payment_notify]

  def index
    @payments = Payment.includes(:user).all.order("date DESC, id DESC")
  end

  def new
    @payment = Payment.new
  end

  def create

    if params[:user_email].present?
      user = User.find_by_email(params[:user_email].downcase)
      params[:payment][:user_id] = user.id if user.present?
    end

    @payment = Payment.create(payment_params)

    if @payment.save
      if user.present? && params["send_thanks"] == 1
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
      user = User.find_by_email(params[:user_email])
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

  def show
    @payment = Payment.find(params[:id])
  end

  def destroy
    @payment = Payment.find(params[:id])
    @payment.destroy
    flash[:notice] = "Payment deleted successfully."
    redirect_to payments_path
  end

  def payment_notify
    plan = "Free"

    # check for GUMROAD
    if params[:email].present? && params[:seller_id].gsub("==","") == ENV['GUMROAD_SELLER_ID'] && params[:product_id].gsub("==","") == ENV['GUMROAD_PRODUCT_ID']
      user = User.find_by_email(params[:email])
      paid = params[:price].to_f / 100
      frequency = paid > 3 ? "Yearly" : "Monthly"
      if user.present? && user.payments.count > 0 && Payment.where(user_id: user.id).last.created_at.to_date === Time.now.to_date
        #duplicate, don't send
      elsif user.present?
        payment = Payment.create(user_id: user.id, comments: "Gumroad #{frequency} from #{user.email}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid )
        UserMailer.thanks_for_paying(user).deliver_later if user.payments.count == 1
      end
      plan = "PRO #{frequency} Gumroad"

      UserMailer.no_user_here(params[:email], "Gumroad").deliver_later if user.blank?

    # check for Paypal
    elsif params[:item_name].present? && params[:item_name].include?("Dabble Me Pro for") && params[:payment_status].present? && params[:payment_status] == "Completed" && ENV['AUTO_EMAIL_PAYPAL'] == "yes"
      email = params[:item_name].gsub("Dabble Me Pro for ","") if params[:item_name].present?
      user = User.find_by_email(email)
      paid = params[:mc_gross]
      frequency = paid > 3 ? "Yearly" : "Monthly"
      if user.blank?
        # try finding user based on payer_email instead of item_name
        email = params[:payer_email] if params[:payer_email].present?
        user = User.find_by_email(email)
      end

      if user.present? && user.payments.count > 0 && Payment.where(user_id: user.id).last.created_at.to_date === Time.now.to_date
        # duplicate, don't send
      elsif user.present?
        payment = Payment.create(user_id: user.id, comments: "Paypal monthly from #{params[:payer_email]}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid )
        UserMailer.thanks_for_paying(user).deliver_later if user.payments.count == 1
      end
      plan = "PRO #{frequency} PayPal"
      UserMailer.no_user_here(email, "PayPal").deliver_later if user.blank?
    end

    user.update(plan: plan) if user.present?
    head :ok, content_type: "text/html"
  end

  private
    def payment_params
      params.require(:payment).permit(:amount, :date, :user_id,  :comments)
    end

    def user_params
      params.permit(:plan)
    end 

    def require_permission
      unless current_user.is_admin?
        flash[:alert] = "Not authorized"
        redirect_to past_entries_path
      end
    end
end
