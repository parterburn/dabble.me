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

    @payment = Payment.create(entry_params)

    if @payment.save
      flash[:notice] = "Payment added successfully!"
      if user.present? && params[:payment][:send_thanks] == 1
        UserMailer.thanks_for_donating(user).deliver_later
      end
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

    if @payment.update(entry_params)
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
    redirect_to payment_path
  end

  def payment_notify
    # check for GUMROAD
    if params[:email].present? && params[:seller_id].gsub("==","") == ENV['GUMROAD_SELLER_ID'] && params[:product_id].gsub("==","") == ENV['GUMROAD_PRODUCT_ID']
      user = User.find_by_email(params[:email])
      if user.present? && user.payments.count > 0 && Payment.where(user_id: user.id).last.created_at.to_date === Time.now.to_date
        #duplicate, don't send
      elsif user.present?
        paid = params[:price].to_f / 100
        payment = Payment.create(user_id: user.id, comments: "Gumroad monthly from #{user.email}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid )
        UserMailer.thanks_for_donating(user).deliver_later if user.payments.count == 1
      end
    elsif params[:item_name].present? && params[:item_name].include?("Dabble Me Pro for") && params[:payment_status].present? && params[:payment_status] == "Completed" && ENV['AUTO_EMAIL_PAYPAL'] == "yes"
      # check for Paypal
      email = params[:item_name].gsub("Dabble Me Pro for ","") if params[:item_name].present?
      user = User.find_by_email(email)

      if user.blank?
        # try finding user based on payer_email instead of item_name
        email = params[:payer_email] if params[:payer_email].present?
        user = User.find_by_email(email)
      end

      if user.present? && user.payments.count > 0 && Payment.where(user_id: user.id).last.created_at.to_date === Time.now.to_date
        # duplicate, don't send
      elsif user.present?
        paid = params[:mc_gross]
        payment = Payment.create(user_id: user.id, comments: "Paypal monthly from #{params[:payer_email]}", date: "#{Time.now.strftime("%Y-%m-%d")}", amount: paid )
        UserMailer.thanks_for_donating(user).deliver_later if user.payments.count == 1
      end
    end

    head :ok, content_type: "text/html"
  end

  private
    def entry_params
      params.require(:payment).permit(:amount, :date, :user_id,  :comments)
    end

    def require_permission
      unless current_user.is_admin?
        flash[:alert] = "Not authorized"
        redirect_to past_entries_path
      end
    end
end
