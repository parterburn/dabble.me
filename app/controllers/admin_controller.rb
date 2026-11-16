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

  # Registered OAuth clients (MCP connectors and the iOS app), grouped by name,
  # with who is connected to each. Filtering lists each registration too.
  def oauth_apps
    @oauth_apps = Admin::OauthApps.new(name: params[:name], email: params[:email])
  end

  # Deletes a client registration. Doorkeeper deletes its tokens and grants
  # with it, which disconnects anyone using it.
  def destroy_oauth_app
    application = Doorkeeper::Application.find(params[:application_id])
    if MobileApp.client?(application)
      redirect_to admin_oauth_apps_path, alert: "The iOS app's client can't be deleted here."
      return
    end

    users = Doorkeeper::AccessToken.where(application_id: application.id, revoked_at: nil).distinct.count(:resource_owner_id)
    application.destroy
    notice = "Deleted #{application.name} (registered #{application.created_at.strftime('%Y-%m-%d')})."
    notice += " #{helpers.pluralize(users, 'user')} disconnected." if users.positive?
    redirect_to admin_oauth_apps_path(name: params[:name].presence, email: params[:email].presence), notice: notice
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

  # The payment form's "Send upgrade email", on its own (User#send_upgrade_email!).
  def send_upgrade_email
    user = User.find(params[:id])
    user.send_upgrade_email!
    redirect_to edit_admin_user_path(user), notice: "Upgrade email sent to #{user.email}."
  end

  # Where an admin announces that Dabble Me is closing, moves the date, or
  # calls it off (SiteClosure).
  def closing
    @closure = site_closure || SiteClosure.new(closes_on: Date.current + 90)
  end

  def announce_closing
    @closure = site_closure || SiteClosure.new
    @closure.closes_on = begin
      Date.iso8601(params[:closes_on].to_s)
    rescue Date::Error
      nil
    end
    if params[:confirm].to_s.strip != SiteClosure::CONFIRMATION
      @closure.validate
      @closure.errors.add(:base, "Type #{SiteClosure::CONFIRMATION} to confirm.")
      return render(:closing, status: :unprocessable_entity)
    end

    @closure = SiteClosure.announce(closes_on: @closure.closes_on, announced_by: current_user)
    return render(:closing, status: :unprocessable_entity) if @closure.errors.any?

    redirect_to admin_closing_path, notice: "Dabble Me now closes on #{@closure.closes_on.strftime('%B %-d, %Y')}."
  end

  def cancel_closing
    SiteClosure.reopen!
    redirect_to admin_closing_path, notice: "The closing is called off. Dabble Me is open again."
  end

  # The one email that goes to everyone with a journal (ServiceNotice): a
  # reminder to export it, under an optional message typed here.
  def notices
    load_notices
  end

  # Emails the notice to the admin alone, to read before it goes to everyone.
  def preview_notice
    load_notices
    if @service_notice.valid?
      ServiceNoticeMailer.export_reminder(current_user, message: @service_notice.message, preview: true).deliver_now
      flash.now[:notice] = "Preview sent to your own address. Nothing went to anyone else."
    end
    render :notices
  end

  # Sends the notice. The count typed has to match the number of people it
  # goes to, so nobody sends it without reading that number.
  def create_notice
    load_notices
    typed = params[:confirm_count].to_s.gsub(/[^\d]/, "")
    if @blocker
      @service_notice.errors.add(:base, @blocker)
    elsif @service_notice.valid? && typed != @recipient_count.to_s
      @service_notice.errors.add(:base, "Type #{@recipient_count} to confirm. That is how many accounts this goes to.")
    end
    return render(:notices, status: :unprocessable_entity) if @service_notice.errors.any?

    sent = ServiceNotice.send_to_everyone!(message: @service_notice.message, sent_by: current_user)
    if sent
      redirect_to admin_notices_path, notice: "Notice queued for #{sent.recipients_count} accounts. They go out at #{ServiceNotice::PER_MINUTE} a minute."
    else
      redirect_to admin_notices_path, alert: "A notice has already gone out today. Nothing was sent."
    end
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

  def load_notices
    @service_notice = ServiceNotice.new(message: params[:message])
    @recipient_count = ServiceNotice.recipients.count
    @blocker = ServiceNotice.blocker
    @past_notices = ServiceNotice.order(created_at: :desc).limit(20).includes(:sent_by)
    @delivered = ServiceNoticeDelivery.where(service_notice_id: @past_notices.map(&:id)).group(:service_notice_id).count
  end

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
