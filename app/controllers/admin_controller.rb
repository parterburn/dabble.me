class AdminController < ApplicationController
  before_action :authenticate_user!
  before_action :authenticate_admin!

  # Kaminari caps a page at 100 (config/initializers/kaminari_config.rb); the photo grid lifts that.
  PHOTOS_PER_PAGE = 300

  def users
    # Each filter that's filled in narrows the list.
    users = User.all
    users = users.where("email ILIKE ?", "%#{params[:email].downcase}%") if params[:email].present?
    if params[:user_key].present?
      # Also matches image_key, so a photo URL's folder leads back to its user.
      # Both keys are encrypted, so this is an exact match on the whole key.
      key = params[:user_key].to_s.strip
      users = users.merge(User.where(user_key: key).or(User.where(image_key: key)))
    end
    users = users.with_name_matching(params[:name]) if params[:name].present?
    @user_list = users.order('id DESC').page(params[:page]).per(per_page)
    @ai_costs = AiUsage.where(user_id: @user_list.map(&:id)).group(:user_id).sum(:cost_usd)
    render 'users'
  end

  def edit_user
    @user = User.find(params[:id])
  end

  def create_ignored_email_image
    @user = User.find(params[:id])
    rule_params = params.require(:ignored_email_image).permit(:kind, :value)
    # Built outside @user.ignored_email_images so a rule that fails to save
    # isn't listed with the saved ones when the page re-renders.
    @ignored_email_image = IgnoredEmailImage.new(user: @user, kind: rule_params[:kind])
    @ignored_email_image.value = rule_params[:value]

    if @ignored_email_image.save
      redirect_to edit_admin_user_path(@user, anchor: "ignored-email-images"), notice: "Their emails will skip that image from now on."
    else
      render 'edit_user', status: :unprocessable_content
    end
  end

  def destroy_ignored_email_image
    user = User.find(params[:id])
    user.ignored_email_images.find(params[:ignored_email_image_id]).destroy
    redirect_to edit_admin_user_path(user, anchor: "ignored-email-images"), notice: "Removed. Their emails can save that image again."
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
    # Paginated in SQL, so a page reads only its own rows.
    @entries = Entry.select(:id, :image, :user_id, :date, :uploading_image_at)
                    .includes(:user)
                    .only_images
                    .order('date DESC')
                    .page(params[:page])
                    .per(params[:per].presence || PHOTOS_PER_PAGE, max_per_page: PHOTOS_PER_PAGE)
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
    params.require(:user).permit(:first_name, :last_name, :email, :send_time, :send_timezone, :send_updates, :plan).tap do |p|
      p.delete(:plan) if p[:plan].blank?
    end
  end
end
