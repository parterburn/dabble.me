class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  def users
    if params[:email].present?
      users = User.where("email ILIKE ?", "%#{params[:email].downcase}%")
    elsif params[:user_key].present?
      # Also matches image_key, so a photo URL's folder leads back to its user.
      users = User.where("user_key ILIKE :key OR image_key ILIKE :key", key: "%#{params[:user_key]}%")
    else
      users = User.all
    end
    @user_list = users.order('id DESC').page(params[:page]).per(per_page)
    render 'users'
  end

  def edit_user
    @user = User.find(params[:id])
  end

  def update_user
    @user = User.find(params[:id])
    @user.assign_attributes(admin_user_params)
    # Every day box shares the name frequency[]; a hidden blank keeps the key
    # present when all are unticked, which turns the emails off.
    @user.frequency = Date::ABBR_DAYNAMES & Array(params[:frequency]) if params.key?(:frequency)
    requested_days = @user.frequency

    if @user.save
      notice = "Saved #{@user.email}."
      # After saving, a Free user's days are cut back to Sunday (User#restrict_free_frequency).
      notice += " Free accounts get Sunday emails only, so the other days were dropped." if @user.reload.frequency != requested_days
      redirect_to edit_admin_user_path(@user), notice: notice
    else
      render 'edit_user', status: :unprocessable_content
    end
  end

  def send_password_reset
    user = User.find(params[:id])
    user.send_reset_password_instructions
    redirect_to edit_admin_user_path(user), notice: "Password reset email sent to #{user.email}."
  end

  def photos
    # `uploading_image_at` is required by Entry#uploading_image? (called through
    # image_code → display_image_url in the view). Keep `:id` for AR identity
    # and any future per-entry actions. Heavy columns like body/original_email
    # stay excluded so the 300-per-page grid stays cheap.
    entries = Entry.select(:id, :image, :user_id, :date, :uploading_image_at)
                   .includes(:user)
                   .only_images
                   .order('date DESC')
    @entries = Kaminari.paginate_array(entries).page(params[:page]).per(per_page)
  end

  def stats
    @dashboard = Admin::Dashboard.new
  end

  def capture_stats
    snapshot = BusinessMetrics::Capture.call
    flash[:notice] = "Snapshot saved for #{snapshot.captured_on}."
    redirect_to admin_stats_path
  end

  private

  def per_page
    params[:per].presence || 300
  end

  # The same basics a user can change on their own settings page, plus plan.
  # Billing IDs stay on the payment form. A blank plan keeps the current one.
  def admin_user_params
    params.require(:user).permit(:first_name, :last_name, :email, :send_time, :send_timezone, :plan).tap do |p|
      p.delete(:plan) if p[:plan].blank?
    end
  end
end
